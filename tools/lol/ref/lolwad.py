"""Minimal, dependency-light WAD (RW 3.x) reader for League of Legends .wad.client files.

Requires: pip install zstandard xxhash
Read-only: opens files with 'rb' only.
"""
from __future__ import annotations

import gzip
import os
import struct
from dataclasses import dataclass

import xxhash
import zstandard

# compression type (low nibble of the type byte)
COMP_NONE, COMP_GZIP, COMP_SATELLITE, COMP_ZSTD, COMP_ZSTD_CHUNKED = range(5)
COMP_NAMES = {0: "none", 1: "gzip", 2: "satellite/redirect", 3: "zstd", 4: "zstd-subchunked"}


def wad_path_hash(path: str) -> int:
    """WAD chunk key = xxHash64(seed=0) of the lower-cased, forward-slash UTF-8 path."""
    return xxhash.xxh64_intdigest(path.lower().replace("\\", "/").encode("utf-8"), 0)


@dataclass(slots=True)
class WadEntry:
    path_hash: int
    offset: int
    compressed_size: int
    size: int
    type: int            # compression type (low nibble)
    subchunk_count: int  # high nibble of the type byte
    subchunk_index: int  # first subchunk index (24-bit in v3.4)
    checksum: int        # v3.1+: xxh3_64 of the stored (compressed) bytes


def _zstd_decompress_all_frames(data: bytes, size_hint: int) -> bytes:
    """Decompress a buffer that may contain several concatenated zstd frames."""
    dctx = zstandard.ZstdDecompressor()
    try:
        # Fast path: single frame that declares its content size
        out = dctx.decompress(data, max_output_size=max(size_hint, 1))
        if len(out) == size_hint:
            return out
    except zstandard.ZstdError:
        pass
    # Robust path: stream across frames
    dobj = dctx.decompressobj()
    parts = []
    view = memoryview(data)
    while view:
        parts.append(dobj.decompress(view.tobytes()))
        rest = dobj.unused_data
        if not rest:
            break
        view = memoryview(rest)
        dobj = dctx.decompressobj()
    return b"".join(parts)


class Wad:
    def __init__(self, path: str, game_root_marker: str = "Game"):
        self.path = path
        self.f = open(path, "rb")
        magic, self.major, self.minor = struct.unpack("<2sBB", self.f.read(4))
        if magic != b"RW":
            raise ValueError("not a WAD")
        if self.major == 3:
            self.f.seek(4 + 256)                      # ECDSA signature (256 bytes)
            (self.data_checksum,) = struct.unpack("<Q", self.f.read(8))
        elif self.major == 2:
            self.f.seek(4 + 1 + 83)                    # ecdsa len(1) + sig(83)
            (self.data_checksum,) = struct.unpack("<Q", self.f.read(8))
            self.f.read(4)                             # toc start u16, toc entry size u16
        elif self.major == 1:
            self.f.read(4)                             # toc start u16, toc entry size u16
        else:
            raise ValueError(f"unsupported WAD {self.major}.{self.minor}")
        (count,) = struct.unpack("<I", self.f.read(4))
        raw = self.f.read(count * (24 if self.major == 1 else 32))
        self.entries: dict[int, WadEntry] = {}
        if self.major == 1:
            for i in range(count):
                h, off, csz, sz, typ = struct.unpack_from("<QIIII", raw, i * 24)
                self.entries[h] = WadEntry(h, off, csz, sz, typ & 0xF, 0, 0, 0)
        else:
            for i in range(count):
                h, off, csz, sz, typ, b5, w6, chk = struct.unpack_from("<QIIIBBHQ", raw, i * 32)
                if (self.major, self.minor) >= (3, 4):
                    sub_index = (b5 << 16) | w6        # 24-bit first-subchunk index
                else:
                    sub_index = w6                     # b5 = "is duplicate" flag in <= 3.3
                self.entries[h] = WadEntry(h, off, csz, sz, typ & 0xF, typ >> 4, sub_index, chk)
        self.subchunk_toc: bytes | None = None
        # The subchunk TOC is itself an entry: '<wad path relative to Game/, lower>' with
        # '.client' replaced by '.subchunktoc', e.g. data/final/champions/ahri.wad.subchunktoc
        norm = os.path.abspath(path).replace("\\", "/")
        low = norm.lower()
        idx = low.rfind("/" + game_root_marker.lower() + "/")
        if idx >= 0:
            rel = low[idx + len(game_root_marker) + 2:]
            toc_path = os.path.splitext(rel)[0] + ".subchunktoc"
            e = self.entries.get(wad_path_hash(toc_path))
            if e is not None:
                self.subchunk_toc = self.read_entry(e)
                self.subchunk_toc_path = toc_path

    def close(self):
        self.f.close()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def raw(self, e: WadEntry) -> bytes:
        self.f.seek(e.offset)
        return self.f.read(e.compressed_size)

    def read_entry(self, e: WadEntry) -> bytes | None:
        data = self.raw(e)
        t = e.type
        if t == COMP_NONE:
            return data
        if t == COMP_GZIP:
            return gzip.decompress(data)
        if t == COMP_SATELLITE:
            return None  # data is a redirect string: u32 len + path; not used in modern game files
        if t == COMP_ZSTD:
            return _zstd_decompress_all_frames(data, e.size)
        if t == COMP_ZSTD_CHUNKED:
            if self.subchunk_toc is None:
                # Every subchunk is an independent zstd frame (or stored raw); try generic path.
                return _zstd_decompress_all_frames(data, e.size)
            out = []
            pos = 0
            dctx = zstandard.ZstdDecompressor()
            for i in range(e.subchunk_index, e.subchunk_index + e.subchunk_count):
                csz, usz, _xxh3 = struct.unpack_from("<IIQ", self.subchunk_toc, 16 * i)
                piece = data[pos:pos + csz]
                if csz == usz:
                    out.append(piece)                  # stored uncompressed
                else:
                    out.append(dctx.decompress(piece, max_output_size=usz))
                pos += csz
            return b"".join(out)
        raise ValueError(f"unknown compression type {t}")

    def get(self, path: str) -> bytes | None:
        e = self.entries.get(wad_path_hash(path))
        return None if e is None else self.read_entry(e)

    def has(self, path: str) -> bool:
        return wad_path_hash(path) in self.entries


MAGICS = [
    (b"r3d2anmd", "anm"), (b"r3d2canm", "anm"), (b"r3d2sklt", "skl(legacy)"), (b"r3d2Mesh", "scb"),
    (b"r3d2", "wpk"), (b"\x33\x22\x11\x00", "skn"), (b"PROP", "bin"), (b"PTCH", "bin(ptch)"),
    (b"TEX\x00", "tex"), (b"DDS ", "dds"), (b"OEGM", "mapgeo"), (b"BKHD", "bnk"), (b"\x89PNG", "png"),
    (b"OggS", "ogg"), (b"\xff\xd8\xff", "jpg"),
]


def guess_kind(data: bytes) -> str:
    for m, k in MAGICS:
        if data.startswith(m):
            return k
    if len(data) >= 8 and struct.unpack_from("<I", data, 4)[0] == 0x22FD4FC3:
        return "skl"
    return "?"
