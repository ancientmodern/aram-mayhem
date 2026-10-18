"""Decoder for League .tex textures (and .dds via Pillow) -> PIL.Image."""
import io
import struct
from PIL import Image

FMT_ETC1, FMT_ETC2_EAC, FMT_ETC2, FMT_BC1, FMT_BC3, FMT_BGRA8 = 1, 2, 3, 10, 12, 20


def _mip_sizes(w, h, block, bpp_block):
    sizes = []
    while True:
        if block:
            bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
            sizes.append((w, h, bw * bh * bpp_block))
        else:
            sizes.append((w, h, w * h * 4))
        if w == 1 and h == 1:
            break
        w, h = max(1, w // 2), max(1, h // 2)
    return sizes


def decode_tex(data: bytes) -> Image.Image:
    if data[:4] == b"DDS ":
        return Image.open(io.BytesIO(data)).convert("RGBA")
    if data[:4] != b"TEX\x00":
        # maybe png/jpg
        return Image.open(io.BytesIO(data)).convert("RGBA")
    w, h, _unk1, fmt, _unk2, flags = struct.unpack_from("<HHBBBB", data, 4)
    has_mips = bool(flags & 1)
    payload = data[12:]
    if fmt == FMT_BC1:
        block, bpb, n = True, 8, 1
    elif fmt == FMT_BC3:
        block, bpb, n = True, 16, 3
    elif fmt == FMT_BGRA8:
        block, bpb, n = False, 0, 0
    else:
        raise ValueError(f"unsupported tex format {fmt}")
    sizes = _mip_sizes(w, h, block, bpb)
    if has_mips:
        # stored smallest mip first; full resolution is last
        total = sum(s[2] for s in sizes)
        off = len(payload) - sizes[0][2] if len(payload) >= total else 0
        raw = payload[off:off + sizes[0][2]]
    else:
        raw = payload[:sizes[0][2]]
    if block:
        img = Image.frombytes("RGBA", (w, h), raw, "bcn", n)
    else:
        img = Image.frombytes("RGBA", (w, h), raw, "raw", "BGRA")
    return img


if __name__ == "__main__":
    import sys
    im = decode_tex(open(sys.argv[1], "rb").read())
    im.save(sys.argv[2])
    print(im.size)
