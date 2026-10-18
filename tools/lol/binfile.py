"""Parser for League BIN property files (PROP / PTCH).

Produces plain Python structures:
  BinFile.entries: {path_hash(u32): BinObject}
  BinObject: .cls (u32 class hash), .fields {name_hash(u32): value}
Field names / class names / entry paths are FNV-1a 32 hashes of lowercased names.
"""
import struct


def fnv1a(s: str) -> int:
    h = 0x811C9DC5
    for c in s.lower().encode("utf-8"):
        h ^= c
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


class BinObject:
    __slots__ = ("cls", "fields")

    def __init__(self, cls, fields):
        self.cls = cls
        self.fields = fields

    def get(self, name, default=None):
        key = name if isinstance(name, int) else fnv1a(name)
        return self.fields.get(key, default)

    def __repr__(self):
        return f"<BinObject cls={self.cls:08x} fields={len(self.fields)}>"


class BinLink(int):
    pass


class BinHash(int):
    pass


class BinFileRef(int):
    pass


T_NONE, T_BOOL, T_I8, T_U8, T_I16, T_U16, T_I32, T_U32, T_I64, T_U64, T_F32, T_VEC2, T_VEC3, T_VEC4, T_MTX, T_RGBA, T_STR, T_HASH, T_FILE = range(19)
T_LIST, T_LIST2, T_PTR, T_EMBED, T_LINK, T_OPTION, T_MAP, T_FLAG = range(0x80, 0x88)


class Reader:
    def __init__(self, data, legacy=False):
        self.d = data
        self.p = 0
        self.legacy = legacy

    def u8(self):
        v = self.d[self.p]
        self.p += 1
        return v

    def unpack(self, fmt, size):
        v = struct.unpack_from(fmt, self.d, self.p)
        self.p += size
        return v

    def typ(self):
        t = self.u8()
        if self.legacy and t >= 18:
            t = t - 18 + 0x80
        return t

    def value(self, t):
        if t == T_BOOL or t == T_FLAG:
            return self.u8() != 0
        if t == T_I8:
            return self.unpack("<b", 1)[0]
        if t == T_U8:
            return self.u8()
        if t == T_I16:
            return self.unpack("<h", 2)[0]
        if t == T_U16:
            return self.unpack("<H", 2)[0]
        if t == T_I32:
            return self.unpack("<i", 4)[0]
        if t == T_U32:
            return self.unpack("<I", 4)[0]
        if t == T_I64:
            return self.unpack("<q", 8)[0]
        if t == T_U64:
            return self.unpack("<Q", 8)[0]
        if t == T_F32:
            return self.unpack("<f", 4)[0]
        if t == T_VEC2:
            return self.unpack("<2f", 8)
        if t == T_VEC3:
            return self.unpack("<3f", 12)
        if t == T_VEC4:
            return self.unpack("<4f", 16)
        if t == T_MTX:
            return self.unpack("<16f", 64)
        if t == T_RGBA:
            return self.unpack("<4B", 4)
        if t == T_STR:
            n = self.unpack("<H", 2)[0]
            s = self.d[self.p:self.p + n].decode("utf-8", "replace")
            self.p += n
            return s
        if t == T_HASH:
            return BinHash(self.unpack("<I", 4)[0])
        if t == T_FILE:
            return BinFileRef(self.unpack("<Q", 8)[0])
        if t in (T_LIST, T_LIST2):
            et = self.typ()
            _size, count = self.unpack("<II", 8)
            return [self.value(et) for _ in range(count)]
        if t in (T_PTR, T_EMBED):
            cls = self.unpack("<I", 4)[0]
            if cls == 0:
                return None
            _size, nf = self.unpack("<IH", 6)
            return BinObject(cls, self.fields(nf))
        if t == T_LINK:
            return BinLink(self.unpack("<I", 4)[0])
        if t == T_OPTION:
            et = self.typ()
            n = self.u8()
            return self.value(et) if n else None
        if t == T_MAP:
            kt = self.typ()
            vt = self.typ()
            _size, count = self.unpack("<II", 8)
            out = {}
            for _ in range(count):
                k = self.value(kt)
                out[k] = self.value(vt)
            return out
        raise ValueError(f"unknown bin type {t} at {self.p}")

    def fields(self, n):
        out = {}
        for _ in range(n):
            name = self.unpack("<I", 4)[0]
            t = self.typ()
            out[name] = self.value(t)
        return out


class BinFile:
    def __init__(self, data: bytes):
        r = Reader(data)
        magic = data[:4]
        if magic == b"PTCH":
            r.p = 16
            magic = data[12:16]
        else:
            r.p = 4
        if magic != b"PROP":
            raise ValueError("not a PROP bin")
        self.version = r.unpack("<I", 4)[0]
        self.links = []
        if self.version >= 2:
            n = r.unpack("<I", 4)[0]
            for _ in range(n):
                ln = r.unpack("<H", 2)[0]
                self.links.append(data[r.p:r.p + ln].decode("utf-8", "replace"))
                r.p += ln
        count = r.unpack("<I", 4)[0]
        types = r.unpack(f"<{count}I", 4 * count)
        self.entries = {}
        for i in range(count):
            length = r.unpack("<I", 4)[0]
            start = r.p
            key, nf = r.unpack("<IH", 6)
            try:
                self.entries[key] = BinObject(types[i], r.fields(nf))
            except Exception:
                pass
            r.p = start + length

    def get(self, path):
        key = path if isinstance(path, int) else fnv1a(path)
        return self.entries.get(key)


def to_py(v, names=None):
    """Convert to JSON-friendly structures, optionally resolving hashes via names dict."""
    names = names or {}
    if isinstance(v, BinObject):
        return {"__class": names.get(v.cls, f"{v.cls:08x}"),
                **{names.get(k, f"{k:08x}"): to_py(x, names) for k, x in v.fields.items()}}
    if isinstance(v, list):
        return [to_py(x, names) for x in v]
    if isinstance(v, tuple):
        return list(v)
    if isinstance(v, dict):
        return {str(to_py(k, names)): to_py(x, names) for k, x in v.items()}
    if isinstance(v, BinLink):
        return "link:" + names.get(int(v), f"{int(v):08x}")
    if isinstance(v, BinHash):
        return "hash:" + names.get(int(v), f"{int(v):08x}")
    if isinstance(v, BinFileRef):
        return f"file:{int(v):016x}"
    return v
