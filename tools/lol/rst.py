"""Reader for RST string tables (lol.stringtable)."""
import struct
import xxhash


class StringTable:
    def __init__(self, data: bytes):
        if data[:3] != b"RST":
            raise ValueError("not RST")
        self.version = data[3]
        pos = 4
        if self.version in (2, 3):
            # optional font config string
            has_cfg = data[pos]
            pos += 1
            if has_cfg:
                n = struct.unpack_from("<I", data, pos)[0]
                pos += 4 + n
        count = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        self.hash_bits = 40 if self.version < 4 else (39 if self.version == 4 else 38)
        mask = (1 << self.hash_bits) - 1
        entries = struct.unpack_from(f"<{count}Q", data, pos)
        pos += 8 * count
        if self.version < 5:
            pos += 1  # has trenc byte
        base = pos
        self.strings = {}
        for e in entries:
            h = e & mask
            off = e >> self.hash_bits
            end = data.index(b"\x00", base + off)
            self.strings[h] = data[base + off:end].decode("utf-8", "replace")
        self.mask = mask

    def key_hash(self, key: str) -> int:
        f = xxhash.xxh3_64_intdigest if self.version >= 5 else xxhash.xxh64_intdigest
        return f(key.lower().encode("utf-8")) & self.mask

    def get(self, key: str):
        return self.strings.get(self.key_hash(key))
