"""Small glTF 2.0 / GLB builder backed by numpy arrays."""
import json
import struct

import numpy as np

FLOAT, USHORT, UINT, UBYTE = 5126, 5123, 5125, 5121
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
TYPE_SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
NP_TYPES = {FLOAT: np.float32, USHORT: np.uint16, UINT: np.uint32, UBYTE: np.uint8}


class Gltf:
    def __init__(self, generator="aram-mayhem-converter"):
        self.j = {"asset": {"version": "2.0", "generator": generator},
                  "scenes": [{"nodes": []}], "scene": 0, "nodes": [], "meshes": [],
                  "accessors": [], "bufferViews": [], "buffers": []}
        self.bin = bytearray()

    def _align(self, n=4):
        while len(self.bin) % n:
            self.bin += b"\x00"

    def buffer_view(self, data: bytes, target=None) -> int:
        self._align(4)
        bv = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target is not None:
            bv["target"] = target
        self.bin += data
        self.j["bufferViews"].append(bv)
        return len(self.j["bufferViews"]) - 1

    def accessor(self, arr, ctype, atype, target=None, minmax=False, normalized=False) -> int:
        a = np.ascontiguousarray(arr, dtype=NP_TYPES[ctype])
        count = a.shape[0] if atype != "SCALAR" or a.ndim > 0 else 1
        bv = self.buffer_view(a.tobytes(), target)
        acc = {"bufferView": bv, "componentType": ctype, "count": int(count), "type": atype}
        if normalized:
            acc["normalized"] = True
        if minmax:
            flat = a.reshape(count, -1)
            acc["min"] = [float(x) for x in flat.min(axis=0)]
            acc["max"] = [float(x) for x in flat.max(axis=0)]
        self.j["accessors"].append(acc)
        return len(self.j["accessors"]) - 1

    def add(self, key, obj) -> int:
        self.j.setdefault(key, []).append(obj)
        return len(self.j[key]) - 1

    def image_png(self, png_bytes: bytes, name: str) -> int:
        bv = self.buffer_view(png_bytes)
        return self.add("images", {"name": name, "mimeType": "image/png", "bufferView": bv})

    def texture(self, image_index: int) -> int:
        if "samplers" not in self.j:
            self.j["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
        return self.add("textures", {"sampler": 0, "source": image_index})

    def write_glb(self, path: str):
        self._align(4)
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, separators=(",", ":")).encode("utf-8")
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<I4s", len(js), b"JSON"))
            f.write(js)
            f.write(struct.pack("<I4s", len(self.bin), b"BIN\x00"))
            f.write(self.bin)
        return total
