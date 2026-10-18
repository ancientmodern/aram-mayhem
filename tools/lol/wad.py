"""Reader for League of Legends WAD archives (v3.x, .wad / .wad.client).

Entries are addressed by xxhash64 of the lowercased forward-slash path.
"""
import gzip
import struct
import xxhash
import zstandard

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"


def path_hash(path: str) -> int:
    return xxhash.xxh64(path.lower().replace("\\", "/").encode("utf-8")).intdigest()


class WadEntry:
    __slots__ = ("hash", "offset", "csize", "size", "ctype", "subchunks", "dup", "sub_index")

    def __repr__(self):
        return f"<WadEntry {self.hash:016x} t={self.ctype} {self.csize}->{self.size}>"


class Wad:
    def __init__(self, filename: str):
        self.filename = filename
        self.f = open(filename, "rb")
        magic, major, minor = struct.unpack("<2sBB", self.f.read(4))
        if magic != b"RW":
            raise ValueError(f"not a WAD: {filename}")
        self.version = (major, minor)
        if major == 3:
            self.f.read(256 + 8)
        elif major == 2:
            ecdsa_len = struct.unpack("<B", self.f.read(1))[0]
            self.f.read(83 + 8 + 2 + 2 + 2)  # signature + checksum + toc fields
        elif major == 1:
            self.f.read(4)
        count = struct.unpack("<I", self.f.read(4))[0]
        self.entries = {}
        esize = 32 if major >= 3 else 24
        raw = self.f.read(count * esize)
        for i in range(count):
            e = WadEntry()
            if major >= 3:
                (e.hash, e.offset, e.csize, e.size, t, e.dup, e.sub_index, _chk) = struct.unpack_from(
                    "<QIIIBBHQ", raw, i * esize)
            else:
                (e.hash, e.offset, e.csize, e.size, t, e.dup, e.sub_index) = struct.unpack_from(
                    "<QIIIBBH", raw, i * esize)
            e.ctype = t & 0x0F
            e.subchunks = t >> 4
            self.entries[e.hash] = e

    def __contains__(self, path):
        h = path if isinstance(path, int) else path_hash(path)
        return h in self.entries

    def read_raw(self, e: WadEntry) -> bytes:
        self.f.seek(e.offset)
        return self.f.read(e.csize)

    def read_entry(self, e: WadEntry) -> bytes:
        data = self.read_raw(e)
        t = e.ctype
        if t == 0:
            return data
        if t == 1:
            return gzip.decompress(data)
        if t == 2:
            raise ValueError("satellite entry (redirect) not supported")
        if t == 3:
            return zstandard.ZstdDecompressor().decompress(data, max_output_size=e.size)
        if t == 4:
            return self._decompress_multi(data, e.size)
        raise ValueError(f"unknown compression type {t}")

    @staticmethod
    def _decompress_multi(data: bytes, size: int) -> bytes:
        """zstd-multi: concatenation of raw and zstd-compressed subchunks."""
        out = bytearray()
        pos = 0
        n = len(data)
        dctx = zstandard.ZstdDecompressor()
        while pos < n and len(out) < size:
            if data[pos:pos + 4] == ZSTD_MAGIC:
                dobj = dctx.decompressobj()
                chunk = dobj.decompress(data[pos:])
                out += chunk
                used = n - pos - len(dobj.unused_data)
                pos += used
            else:
                nxt = data.find(ZSTD_MAGIC, pos)
                if nxt < 0:
                    nxt = n
                out += data[pos:nxt]
                pos = nxt
        return bytes(out[:size])

    def read(self, path) -> bytes | None:
        h = path if isinstance(path, int) else path_hash(path)
        e = self.entries.get(h)
        if e is None:
            return None
        return self.read_entry(e)

    def close(self):
        self.f.close()


if __name__ == "__main__":
    import sys
    from collections import Counter
    w = Wad(sys.argv[1])
    print("version", w.version, "entries", len(w.entries))
    print(Counter(e.ctype for e in w.entries.values()))
    for p in sys.argv[2:]:
        d = w.read(p)
        print(p, None if d is None else len(d), d[:16] if d else "")
