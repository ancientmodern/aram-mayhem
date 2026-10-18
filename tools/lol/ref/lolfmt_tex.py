"""TEX ('TEX\\0') -> Pillow image. Pillow >= 9 ships a BCn decoder ('bcn'), so no DDS wrapping needed."""
from __future__ import annotations

import io
import struct

from PIL import Image

# format byte -> (name, bcn n or None, block bytes, block dim)
TEX_FORMATS = {
    1: ("ETC1", None, 8, 4),
    2: ("ETC2_EAC", None, 16, 4),
    3: ("ETC2_EAC", None, 16, 4),
    10: ("BC1/DXT1", 1, 8, 4),
    11: ("BC1/DXT1", 1, 8, 4),
    12: ("BC3/DXT5", 3, 16, 4),
    13: ("BC7", 7, 16, 4),       # per LeagueToolkit; not observed in Ahri.wad
    14: ("BC5", 5, 16, 4),       # per LeagueToolkit; not observed in Ahri.wad
    20: ("BGRA8", None, 4, 1),
}


def parse_tex_header(d: bytes):
    magic, w, h, unk, fmt, res_type, flags = struct.unpack_from("<4sHHBBBB", d, 0)
    if magic != b"TEX\0":
        raise ValueError("not TEX")
    return dict(width=w, height=h, unk=unk, format=fmt, resource_type=res_type, flags=flags,
                has_mips=bool(flags & 1))


def tex_mip_sizes(w, h, fmt, has_mips):
    name, n, bb, bd = TEX_FORMATS[fmt]
    count = (max(w, h).bit_length()) if has_mips else 1   # floor(log2(max)) + 1
    sizes = []
    for i in range(count):
        mw, mh = max(w >> i, 1), max(h >> i, 1)
        sizes.append((mw, mh, ((mw + bd - 1) // bd) * ((mh + bd - 1) // bd) * bb))
    return sizes  # index 0 = full size


def tex_to_image(d: bytes, mip: int = 0) -> Image.Image:
    hd = parse_tex_header(d)
    sizes = tex_mip_sizes(hd["width"], hd["height"], hd["format"], hd["has_mips"])
    # Data after the 12-byte header stores mips SMALLEST FIRST; the full-size mip is at the END.
    end = len(d)
    for i, (mw, mh, sz) in enumerate(sizes):
        start = end - sz
        if i == mip:
            blob = d[start:end]
            break
        end = start
    name, n, bb, bd = TEX_FORMATS[hd["format"]]
    if n is not None:
        mode = {4: "L", 5: "RGB"}.get(n, "RGBA")       # Pillow: BC4 -> L, BC5 -> RGB (B=0), others RGBA
        return Image.frombuffer(mode, (mw, mh), blob, "bcn", n, "")  # decoder args: (n, pixel_format)
    if name == "BGRA8":
        return Image.frombuffer("RGBA", (mw, mh), blob, "raw", "BGRA", 0, 1)
    raise NotImplementedError(f"TEX format {name} (ETC) needs a separate decoder")


def any_texture_to_image(d: bytes) -> Image.Image:
    if d[:4] == b"TEX\0":
        return tex_to_image(d)
    if d[:4] == b"DDS ":
        return Image.open(io.BytesIO(d))
    raise ValueError("unknown texture container")
