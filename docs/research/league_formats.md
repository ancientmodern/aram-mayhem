# League of Legends client file formats: implementation spec for a WAD → glTF 2.0 (.glb) converter

Target: a Python 3.13 converter that turns champion WADs into glTF 2.0 `.glb` files (meshes, skeletons,
animations, textures) for Godot 4.

Verified against the locally installed client, **patch 16.20.824.8524**
(`D:\Riot Games\League of Legends\Game\League of Legends.exe` FileVersion). Every file was opened read-only.

Every claim below is tagged:

* **[VERIFIED]**: a probe script parsed real game files and the result was checked. Section 9 has the probe outputs.
* **[SOURCE]**: taken from LeagueToolkit (C#), CDTB, pyRitoFile/LtMAO or ritobin source code, and not checked against local files.
* **[UNCERTAIN]**: inferred or unknown.

Probe scripts and reference modules are in
`C:\Users\ancie\AppData\Local\Temp\claude\D--Games-ARAM-Mayhem\23483de4-1c7d-4247-88f4-98ceb1683dfc\scratchpad\formats\`.
That folder is session-scratch and may get cleaned up, so the verified reader modules are also copied verbatim into the **Appendix**.

Python deps: `pip install --user zstandard xxhash` (Pillow 12.3 was already installed). numpy is not required but makes the vertex code much faster.

---

## 0. Quick facts (cheat sheet)

| Thing | Rule | Status |
|---|---|---|
| All multi-byte values | **little-endian** | VERIFIED |
| WAD path key | `xxh64(path.lower(), seed=0)` (UTF-8, forward slashes) | VERIFIED |
| WAD version in game | **RW 3.4** for all 174 champion WADs and Map12 | VERIFIED |
| WAD compression types used | 0 none, 3 zstd, 4 zstd-subchunked. Types 1 and 2 are absent from all champion WADs | VERIFIED |
| BIN field / class / entry-path / hash-value names | `fnv1a32(name.lower())` | VERIFIED |
| BIN `file` type (id 18) | u64 = **the WAD key itself** (xxh64 of the path), so no string is stored | VERIFIED |
| Joint name hash (SKL lookup table, ANM tracks) | ELF hash of the lower-cased name | VERIFIED (211/211 joints) |
| Skin bin | `data/characters/<champ>/skins/skin<N>.bin` | VERIFIED |
| Animation graph bin | `data/characters/<champ>/animations/skin<N>.bin` (listed in skin bin dependencies) | VERIFIED |
| Mesh / skeleton paths | Plain strings in the skin bin, e.g. `ASSETS/Characters/Ahri/Skins/Base/Ahri_Base.skn` | VERIFIED |
| Texture / .anm paths | **Not stored as strings**. They are `file` hashes in current bins | VERIFIED |
| Handedness | League is **left-handed** (Y up, model front +Z). Mirror X for glTF | VERIFIED (by anatomy, see §7) |
| Units | ~1 unit ≈ 1 cm (Ahri is 206 units tall) → scale 0.01 to meters | VERIFIED (sizes) |
| Triangle winding | Raw data is CCW-front in a right-handed reading. **After mirroring X, swap two indices** | VERIFIED |
| UV origin | Top-left (D3D), same as glTF, so leave V as is | VERIFIED (texture looks correct) |

Census of format versions across **all 174 champion WADs** (every entry decompressed) [VERIFIED]:

```
wad 3.4: 174 | compression 0: 2992, 3 (zstd): 186051, 4 (subchunked): 300411
skn 0.1: 5 | 1.1: 10 | 2.1: 562 | 4.1 vtype=0 (52B): 4861 | 4.1 vtype=1 (56B): 306 | 4.1 vtype=2 (72B): 18
skl modern (0x22FD4FC3) v0: 5772 | legacy r3d2sklt: 0
anm r3d2anmd v3: 854 | v4: 2811 | v5: 14433 | r3d2canm v1: 19338 (flags vary: 0x1..0x3d; 0x4 = parametrized)
tex fmt 10 (BC1): 118404 | fmt 12 (BC3): 239047 | fmt 14 (BC5): 9 | fmt 20 (BGRA8): 1
dds DXT1: 2501 | DXT3: 6 | DXT5: 416
bin PROP v3: 23201 (no PTCH, no other versions inside champion WADs)
scb (static mesh, r3d2Mesh): 53235
```

So the converter must handle SKN v0/1/2/4, modern SKL only, ANM v3/v4/v5 plus compressed v1, TEX BC1/BC3/BC5/BGRA8, and DDS.

---

## 1. WAD (`.wad.client`, magic `RW`)

### 1.1 Header

v3.x header (272 bytes) [SOURCE LTK `WadFile.cs` + CDTB `wad.py`; VERIFIED for 3.4]:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 2 | magic `"RW"` |
| 2 | 1 | major (3) |
| 3 | 1 | minor (**4** in 16.20) |
| 4 | 256 | ECDSA signature (ignore) |
| 260 | 8 | u64 checksum (ignore) |
| 268 | 4 | u32 entry count |
| 272 | 32·N | entry table (TOC) |

Older versions (not used by the current game; implement only if you care):
* v1: magic+ver(4), u16 toc_start, u16 toc_entry_size, u32 count at offset 8. Entries are 24 bytes `<QIIII>` (hash, offset, csize, size, type).
* v2: magic+ver(4), u8 ecdsa_len, 83-byte signature, u64 checksum, u16 toc_start, u16 toc_entry_size, u32 count at offset 100. Entries are 32 bytes, as in v3.0.

### 1.2 Entry (32 bytes)

The table is sorted ascending by path hash [VERIFIED].

| Offset | Type | Field |
|---:|---|---|
| 0 | u64 | path hash (xxh64 of the lower-cased path) |
| 8 | u32 | absolute data offset in the file |
| 12 | u32 | stored (compressed) size |
| 16 | u32 | uncompressed size |
| 20 | u8 | low nibble = compression type; high nibble = subchunk count |
| 21 | u8 | **v3.0–3.3:** "is duplicate" bool. **v3.4:** bits 16–23 of the first-subchunk index |
| 22 | u16 | first subchunk index (bits 0–15) |
| 24 | u64 | checksum = `xxh3_64(stored bytes)` (v3.1+; v3.0 used the first 8 bytes of SHA-256) |

* The 24-bit subchunk index in v3.4 comes from CDTB. LTK still reads byte 21 as a bool, which is wrong for 3.4.
* The checksum rule was VERIFIED on 300/300 entries.
* Several path hashes can point at the same data offset (deduplicated data; Ahri has 4508 such entries). This is harmless.

Struct format for v3.4: `struct.unpack_from("<QIIIBBHQ", toc, 32*i)`, then `sub_index = (b21 << 16) | w22`.

### 1.3 Compression types (low nibble)

| Id | Meaning | How to decode in Python | Seen in 16.20 |
|---:|---|---|---|
| 0 | none | raw bytes | yes |
| 1 | gzip | `gzip.decompress(data)` | no |
| 2 | "satellite" / file redirect | payload is `u32 len + path string`. Skip it (CDTB returns None) | no |
| 3 | zstd | `zstandard.ZstdDecompressor().decompress(data, max_output_size=size)`. Every Ahri type-3 entry is a single frame whose header declares the content size [VERIFIED]. For robustness, fall back to a `decompressobj()` loop for concatenated frames | yes |
| 4 | zstd **subchunked** | see below | yes (most entries) |

**Subchunked entries (type 4).** The stored data is a concatenation of `subchunk_count` subchunks. Each subchunk is either one zstd frame or stored raw.

* The subchunk table is itself a WAD entry. Its path is the WAD's own path relative to the `Game/` folder, lower-cased, with `.client` replaced by `.subchunktoc`. Examples:
  * `data/final/champions/ahri.wad.subchunktoc`
  * `data/final/maps/shipping/map12.wad.subchunktoc`
* That entry is a packed array of 16-byte records `<IIQ>`: compressed size, uncompressed size, `xxh3_64` of the compressed subchunk.
* An entry uses records `[first_index, first_index + subchunk_count)`.
* If `compressed == uncompressed`, the subchunk is stored raw. Otherwise it is a zstd frame. This is the CDTB rule; LTK tries zstd and falls back to a raw copy.

Ahri: 3644 type-4 entries, 2–3 subchunks each, 9195 TOC records, every record hash checked, 0 raw subchunks [VERIFIED]. You need the TOC because raw subchunks would break a naive "decompress all frames" approach.

Probe result [VERIFIED]: all 6078 Ahri entries decompress to their declared sizes. Per file type: tex 4397, anm 731, scb 519, bin 229, skl 73, skn 69, bnk 36, dds 21.

### 1.4 Path hashing and finding files

```python
import xxhash
def wad_path_hash(path: str) -> int:
    return xxhash.xxh64_intdigest(path.lower().replace("\\", "/").encode("utf-8"), 0)
```

[VERIFIED]

| Path | Hash | In Ahri.wad.client? |
|---|---|---|
| `assets/characters/ahri/skins/base/ahri_base.skn` | `fca50cac17fc3470` | yes (zstd, 452884 → 847032 bytes) |
| `assets/characters/ahri/skins/base/ahri_base.skl` | `7af569a936e17949` | yes |
| `assets/characters/ahri/skins/base/ahri.skn` (the path suggested in the task) | `82b4e8e145123090` | **no**. This is a historical name that still appears in hashes.game.txt. Modern skins are named `<champ>_<skin>.skn` |

**Finding files without a hash list:**

1. Fixed, guessable bin paths:
   * `data/characters/<champ>/skins/skin<N>.bin` (N = 0, 1, 2, …)
   * `data/characters/<champ>/<champ>.bin` (character record)
   * `data/characters/<champ>/animations/skin<N>.bin`
2. Inside the skin bin, `skinMeshProperties.simpleSkin` and `.skeleton` are **plain strings**. Hash them to get their WAD keys.
3. Textures (`texture`, `texturePath`) and animations (`mAnimationFilePath`) are BIN `file` values: a u64 that **is the WAD key**. Look them up directly with `wad.entries[value]`; no path is needed.
4. Without a hash list you will not know the file *names* of textures and .anm files, only their keys. For human-readable clip names, either:
   * stream CommunityDragon's `hashes.game.txt` (format `"<16 hex> <path>\n"`; ~232 MB, ~2.3 M lines, ~11 s to stream and filter), or
   * use the clip-name hashes from the animation graph (§2.6).
5. Content sniffing by magic bytes (CDTB `guess_extension`):

   | Magic | Format |
   |---|---|
   | `r3d2anmd` / `r3d2canm` | anm |
   | `33 22 11 00` | skn |
   | `PROP` / `PTCH` | bin |
   | `TEX\0` | tex |
   | `DDS ` | dds |
   | `OEGM` | mapgeo |
   | `r3d2Mesh` | scb |
   | `r3d2sklt` | legacy skl |
   | u32 at offset 4 == `0x22FD4FC3` | modern skl |

CommunityDragon hash lists live at `https://raw.communitydragon.org/data/hashes/lol/` (send a browser-like `User-Agent`, otherwise you get 403):

| File | Contents |
|---|---|
| `hashes.game.txt` | WAD paths (xxh64) |
| `hashes.binentries.txt` | object paths (FNV) |
| `hashes.binfields.txt` | field names |
| `hashes.bintypes.txt` | class names |
| `hashes.binhashes.txt` | `hash`-typed values |

---

## 2. BIN property files (`PROP` / `PTCH`)

### 2.1 File layout

[SOURCE LTK `BinTree.cs`, ritobin `bin_io_binary_read.cpp`; VERIFIED on PROP v3]

```
[optional patch header]  "PTCH"  u64 unknown (LTK reads it as u32 version=1 + u32 count)
"PROP"
u32 version                       (3 everywhere in 16.20 champion WADs)
if version >= 2:
    u32 dependency_count
    dependency_count × { u16 len; char[len] path }       # "linked" bins, e.g. DATA/Characters/Ahri/Animations/Skin0.bin
u32 object_count
u32 class_hash[object_count]                             # fnv1a(class name), one per object
object_count × {
    u32 byte_size                                        # size of the rest of this object (from path_hash on)
    u32 path_hash                                        # fnv1a("Characters/Ahri/Skins/Skin0")
    u16 field_count
    field_count × field
}
if PTCH:                                                 # patch section (ritobin reads it for any PTCH)
    u32 patch_count
    patch_count × { u32 object_path_hash; u32 byte_size; u8 type; u16 len + char[len] field_path; value }

field = { u32 name_hash; u8 type; value }
```

### 2.2 Type table

These are the current ids. ritobin names are in parentheses.

| Id | Type | Payload |
|---:|---|---|
| 0 | none | nothing |
| 1 | bool | u8 |
| 2 / 3 | i8 / u8 | 1 byte |
| 4 / 5 | i16 / u16 | 2 bytes |
| 6 / 7 | i32 / u32 | 4 bytes |
| 8 / 9 | i64 / u64 | 8 bytes |
| 10 | f32 | 4 bytes |
| 11 / 12 / 13 | vec2 / vec3 / vec4 | 2/3/4 × f32 |
| 14 | mtx44 | 16 × f32 (row-major) |
| 15 | rgba (color) | 4 × u8 (R, G, B, A) |
| 16 | string | u16 length + UTF-8 bytes (no terminator) |
| 17 | hash | u32 fnv1a of a lower-cased string |
| 18 | **file** (WadChunkLink) | **u64 xxh64 of a lower-cased WAD path, i.e. the WAD key** |
| 0x80 | list (container) | u8 element type, u32 byte_size, u32 count, count × value |
| 0x81 | list2 (unordered container) | same as list |
| 0x82 | pointer (struct) | u32 class_hash. If 0 the value is null and nothing follows. Otherwise u32 byte_size, u16 field_count, fields |
| 0x83 | embed (embedded) | same as pointer |
| 0x84 | link (object link) | u32 fnv1a of the target object's path |
| 0x85 | option | u8 element type, u8 present (0/1), value if present |
| 0x86 | map | u8 key type, u8 value type, u32 byte_size, u32 count, count × (key, value) |
| 0x87 | flag (bitbool) | u8 |

**Legacy type ids.** In bins written before `file` was inserted, complex types were 18–24. LTK detects an invalid type, then re-reads the file with this remap: `if 18 <= t < 0x80: t = (t-18) | 0x80; if t >= 0x81: t += 1`. No current file needed this [VERIFIED: every parse succeeded with current ids].

**Hashes** [VERIFIED]:
* Class, field, object-path and hash-value names all use `fnv1a32(lowercase)`: start `0x811C9DC5`, then for each byte `h = (h ^ b) * 0x01000193 mod 2^32`.
* Because names are lower-cased before hashing, a class name and a field name that differ only in case have the same hash (e.g. class `SkinAnimationProperties` and field `skinAnimationProperties`).

### 2.3 Pragmatic approach: ASCII scan (and why it is not enough)

[VERIFIED] Scanning `skin0.bin` for printable strings (each real bin string is preceded by its u16 length; use that to trim junk) finds only:

* `ASSETS/Characters/Ahri/Skins/Base/Ahri_Base.skn`
* `ASSETS/Characters/Ahri/Skins/Base/Ahri_Base.skl`
* the dependency bins, including `DATA/Characters/Ahri/Animations/Skin0.bin`
* sound bank paths and material object names

It does **not** find textures or .anm files, because they are `file` hashes in 16.20. So you need the real parser (Appendix `lolbin.py`, about 150 lines). A middle ground also works: find the 4-byte field name hash followed by type byte `0x12`, then read the u64 after it.

### 2.4 Skin bin structure (Ahri skin0, real dump, abbreviated)

```
Characters/Ahri/Skins/Skin0 = SkinCharacterDataProperties {          # object path hash = fnv1a(that path)
  championSkinName: string = 'Ahri'
  skinAnimationProperties: embed = SkinAnimationProperties {
    animationGraphData: link = Characters/Ahri/Animations/Skin0     # object inside DATA/Characters/Ahri/Animations/Skin0.bin
  }
  skinMeshProperties: embed = SkinMeshDataProperties {
    skeleton:   string = 'ASSETS/Characters/Ahri/Skins/Base/Ahri_Base.skl'
    simpleSkin: string = 'ASSETS/Characters/Ahri/Skins/Base/Ahri_Base.skn'
    texture:    file   = 0x12cf9c27d09be6c5     # = assets/characters/ahri/skins/base/ahri_base_tx_cm.tex (WAD key)
    selfIllumination: f32 = 0.7
    initialSubmeshToHide: string = 'Tail_Large Body_Proxy'    # space-separated submesh names hidden by default
    materialOverride: list[embed SkinMeshDataProperties_MaterialOverride] = [
      { texture: file = 0xdf549b7becf3810a  submesh: 'Tail_Large' }                          # texture-only override
      { material: link = Characters/Ahri/Skins/Skin0/Materials/MAT_Tails_inst  submesh: 'Tails' }
      { material: link = Characters/Ahri/Skins/Skin0/Materials/MAT_Body_inst   submesh: 'Body' }
    ]
    # optional fields seen elsewhere: material (default link), skinScale (f32), boundingCylinder..., rigPoseModifierData
  }
  ...
}
Characters/Ahri/Skins/Skin0/Materials/MAT_Body_inst = StaticMaterialDef {
  name: string = 'Characters/Ahri/Skins/Skin0/Materials/MAT_Body_inst'
  samplerValues: list2[embed StaticMaterialShaderSamplerDef] = [
    { textureName: 'Diffuse_Texture'   texturePath: file = 0x12cf9c27d09be6c5  addressU/V/W: u32 = 1 }
    { textureName: 'Diffuse_Texture_2' texturePath: file = (R-ult texture swap) }
    { textureName: 'Scroll_Texture'    texturePath: file = assets/shared/materials/black.tex }
  ]
  paramValues: list2[{name: string, value: vec4}]   switches: list2[{name, on}]
  techniques: [{name:'normal', passes:[{shader: link = Shaders/SkinnedMesh/2_Diffuse_Lerp, blendEnable...}]}]
}
```

**Resolving the texture for each SKN submesh** [VERIFIED for Ahri]:

1. Use the matching `materialOverride` entry (match `submesh` against the SKN range name, case-insensitively):
   * If it has `texture` (a `file`), use that.
   * Otherwise follow its `material` link to a `StaticMaterialDef`. Look for it in this bin first, then in the linked dependency bins, which can define shared materials. Take the sampler whose `textureName` contains `"Diffuse"` (`Diffuse_Texture` for champions, `DiffuseTexture` in map materials). Fall back to the first sampler.
2. If there is no override, use `skinMeshProperties.texture`. If only `skinMeshProperties.material` exists, resolve it as above.
3. Submeshes named in `initialSubmeshToHide` are hidden in game (alternate or ability meshes). Export them hidden or skip them.
4. Apply `skinScale` (default 1.0) as a uniform scale if it is present [SOURCE / UNCERTAIN on exact semantics].
5. Older bins stored `texture`/`texturePath` as `string` (the patch where this changed is **[UNCERTAIN]**). Accept both string and file: hash the string to get the WAD key.

### 2.5 Animation graph bin

[VERIFIED on `DATA/Characters/Ahri/Animations/Skin0.bin`]

```
Characters/Ahri/Animations/Skin0 = AnimationGraphData {
  mClipDataMap: map<hash, pointer> = {
    fnv1a("Attack1") => AtomicClipData {
      mTrackDataName: hash = Default
      mEventDataMap: map {...}                                    # particle/sound events (frames)
      mAnimationResourceData: embed AnimationResourceData {
        mAnimationFilePath: file = 0xc867d45041a3528e            # assets/characters/ahri/skins/base/animations/attack1.anm
      }
    }
    fnv1a("Channel") => AtomicClipData { mFlags: u32 = 2 ... }
    ... SequencerClipData / SelectorClipData / ConditionBoolClipData / ConditionFloatClipData / ParallelClipData
        reference other clips by name hash (blend logic). Only AtomicClipData points at .anm files.
  }
  mMaskDataMap, mTrackDataMap, mBlendDataTable ...                 # not needed for export
}
```

Ahri skin0 has 72 clips: 55 Atomic, 8 Sequencer, 5 ConditionBool, 2 ConditionFloat, 2 Selector. All 55 `.anm` file keys are present in the WAD.

**Clip names** are FNV hashes. These were confirmed by hashing guesses: `Attack1`, `Attack2`, `Crit`, `Death`, `Channel`, `Idle_In`, `Laugh`, `Recall`, `Respawn`. Most others are unknown (`Idle1` is **not** `fnv1a("Idle1")`). Naming strategy:
1. Use the `.anm` basename from the CDragon hash list (e.g. `idle1`, `run`, `dance_loop`).
2. Otherwise use a guessed clip name.
3. Otherwise use `clip_<hash:08x>`.

Several clips can point at the same .anm (e.g. `Respawn` and another clip both use `respawn.anm`), so de-duplicate by file key.

---

## 3. SKN, SimpleSkin (magic `0x00112233`)

[SOURCE LTK `SkinnedMesh.cs`, pyRitoFile `skn.py`; VERIFIED on v0.1, v1.1, v2.1, v4.1]

### 3.1 Layout

```
u32 magic = 0x00112233
u16 major, u16 minor            # (0,1) (1,1) (2,1) (4,1) seen
if major == 0:
    u32 index_count, u32 vertex_count          # single implicit range "Base"
else:
    u32 range_count
    range_count × { char material[64] (NUL-padded); u32 start_vertex; u32 vertex_count; u32 start_index; u32 index_count }   # 80 B
    if major == 4: u32 flags                   # 0 in Ahri
    u32 index_count, u32 vertex_count
    if major == 4:
        u32 vertex_size                         # 52 / 56 / 72
        u32 vertex_type                         # 0 basic / 1 color / 2 tangent
        f32 bbox_min[3], bbox_max[3]
        f32 sphere_center[3], sphere_radius
u16 indices[index_count]                        # triangle list; values are ABSOLUTE vertex indices
vertex[vertex_count]
(v2.1 files may have 12 trailing zero bytes; ignore anything after the vertices)
```

### 3.2 Vertex layouts

Versions before 4 always use the basic 52-byte layout.

| Offset | Type | Element | basic (52) | color (56) | tangent (72) |
|---:|---|---|:-:|:-:|:-:|
| 0 | 3×f32 | position | ✓ | ✓ | ✓ |
| 12 | 4×u8 | blend indices (**influence slots**, not joint ids) | ✓ | ✓ | ✓ |
| 16 | 4×f32 | blend weights (sum 1.0) | ✓ | ✓ | ✓ |
| 32 | 3×f32 | normal | ✓ | ✓ | ✓ |
| 44 | 2×f32 | uv0 | ✓ | ✓ | ✓ |
| 52 | 4×u8 | color, **B,G,R,A** byte order | | ✓ | ✓ |
| 56 | 4×f32 | tangent xyz + w (handedness sign) | | | ✓ |

### 3.3 Skinning indirection

The vertex joint byte `b` indexes the **SKL influences table**: `joint_id = skl.influences[b]`. `joint_id` is then an index into `skl.joints`.

Ahri: 177 influences out of 211 joints; the largest joint byte is 176 [VERIFIED]. Skinning with this mapping, the SKL inverse binds and real animations produces sane posed meshes (§9 probe h).

### 3.4 Ahri result

[VERIFIED] v4.1, vertex_type 0, 13780 vertices, 65034 indices (21678 triangles, 48 of them degenerate).

Ranges:
* `Body` v[0+9721] i[0+45162]
* `Eyes` v[9721+226]
* `Tails` v[9947+3450]
* `Tail_Large` v[13397+383]

The indices of each range stay inside that range's vertex span; they are absolute, not rebased. bbox: x ±157.5, y 0..205.9, z −196.4..18.3 (tails extend to −Z).

### 3.5 Gotchas

* Indices are absolute. If you emit one glTF primitive per range with its own sliced vertex arrays, subtract `start_vertex`. Alternatively, share one vertex buffer across all primitives and keep the indices as they are.
* pyRitoFile drops degenerate triangles. That is optional.
* The LTK version check is `major not in (0,2,4) and minor != 1`, which accepts 1.1.

---

## 4. SKL (skeleton)

### 4.1 Modern format

Detect it by u32 at offset 4 == `0x22FD4FC3`. This is the only variant found in the 16.20 champion WADs (5772 files) [VERIFIED].

**Header (64 bytes)** [SOURCE LTK `RigResource.cs`; VERIFIED]:

| Offset | Type | Field | Ahri value |
|---:|---|---|---|
| 0 | u32 | file size | 25908 |
| 4 | u32 | format token `0x22FD4FC3` | |
| 8 | u32 | version (must be 0) | 0 |
| 12 | u16 | flags | 0 |
| 14 | u16 | joint count | 211 |
| 16 | u32 | influence count | 177 |
| 20 | i32 | joints offset | 64 |
| 24 | i32 | joint-index (hash lookup) offset | 21164 |
| 28 | i32 | influences offset | 22852 |
| 32 | i32 | name offset (C string) | 23208 (empty) |
| 36 | i32 | asset name offset (C string) | 23212 (empty) |
| 40 | i32 | joint names offset | 23216 |
| 44 | 5×i32 | reserved | −1 |

**Joint record (100 bytes, `joint_count` of them at `joints_offset`):**

| Offset | Type | Field |
|---:|---|---|
| 0 | u16 | flags (0 for all Ahri joints) |
| 2 | i16 | id (== array index) |
| 4 | i16 | parent id (−1 = root; there can be several roots) |
| 6 | u16 | padding |
| 8 | u32 | name hash = ELF(lower(name)) |
| 12 | f32 | radius (2.1 everywhere) |
| 16 | 3×f32 | local translation |
| 28 | 3×f32 | local scale |
| 40 | 4×f32 | local rotation quaternion **x, y, z, w** |
| 56 | 3×f32 | inverse-bind translation |
| 68 | 3×f32 | inverse-bind scale |
| 80 | 4×f32 | inverse-bind rotation quaternion x, y, z, w |
| 96 | i32 | name offset **relative to the address of this field** (`name_at = record + 96 + value`) |

**Other sections:**
* Joint-index table: `joint_count × { i16 id; u16 pad; u32 elf_hash }`, sorted by hash. This is how the game maps ANM track hashes to joints.
* Influences: `influence_count × i16 joint_id`.

**Transforms:**
* Local transforms are relative to the parent joint. Compose as `M = T · R · S` (column vectors; glTF convention).
* The inverse-bind TRS composes the same way and gives the joint's inverse bind matrix directly.
* Check: `Global(local chain) · TRS(ibind) ≈ I` holds to 0.0033 at most, and only along 10-joint tail chains (≈0.19°). This is inherent float drift in the file, not a parsing error.
* **Use the file's inverse-bind for glTF `inverseBindMatrices`** to match the game exactly. Otherwise compute `inverse(global_bind)` for a perfectly rigid rest pose; the difference is under 0.65 units on Ahri's tail tips.

**Ahri details** [VERIFIED]:
* Two roots: `Root` and `C_Buffbone_Glb_Center_Loc`.
* `Root` has local rotation `(0, 1, 0, 0)`, i.e. 180° about Y, and translation (0, 127.2, 0.8).
* All parents come before their children. All ids equal their array index.
* name_hash == ELF(lower(name)) for all 211 joints, and the hash table matches.

ELF hash (used for SKL and ANM):

```python
def elf_hash(name: str) -> int:
    h = 0
    for c in name.lower().encode("ascii"):
        h = ((h << 4) + c) & 0xFFFFFFFF
        high = h & 0xF0000000
        if high: h ^= high >> 24
        h &= ~high & 0xFFFFFFFF
    return h
```

### 4.2 Legacy `r3d2sklt`

[SOURCE only; absent from 16.20 champion WADs]

```
char magic[8] = "r3d2sklt"; u32 version (1|2); u32 skeleton_id; u32 joint_count
joint_count × { char name[32]; i32 parent; f32 radius; f32 m[12] }   # 88 B; m = 3 rows of (r0 r1 r2 t): global/world 3x4
v2: u32 influence_count; u32 influences[influence_count]
v1: influences = identity (0..joint_count-1)
```

To get local transforms: `local = global` for roots, otherwise `local = inverse(global_parent) · global` (column-vector form). The inverse bind is `inverse(global)`. Joint hash = ELF(lower(name)).

---

## 5. ANM (animations)

Joint matching applies to every variant: track key = ELF(lower(joint name)), matched against SKL joint `name_hash`. Ahri tracks match 211/211 for v5 and compressed. An old v4 file (`joke_loop`) has 236 tracks, of which 210 match; ignore unknown tracks. Joints with no track keep their bind local TRS.

The animated TRS values are **local** (parent-relative) transforms in the same space as the SKL local TRS. Unanimated `Pelvis` equals its bind local exactly [VERIFIED].

**All offsets in r3d2anmd v4/v5 and r3d2canm are relative to byte 12** (just after magic[8] + version u32). The LTK readers seek `offset + 12`.

### 5.1 `r3d2anmd` v5 (most common uncompressed)

[SOURCE LTK `UncompressedAnimationAsset.cs`; VERIFIED]

| Offset | Type | Field |
|---:|---|---|
| 0 | char[8] | `r3d2anmd` |
| 8 | u32 | version = 5 |
| 12 | u32 | resource size |
| 16 | u32 | format token (0) |
| 20 | u32 | version (0) |
| 24 | u32 | flags (0) |
| 28 | i32 | track count |
| 32 | i32 | frame count |
| 36 | f32 | frame duration in seconds (1/30) |
| 40 | i32 | joint name hashes offset |
| 44 | i32 | asset name offset (0) |
| 48 | i32 | time offset (0) |
| 52 | i32 | vector palette offset |
| 56 | i32 | quat palette offset |
| 60 | i32 | frames offset |

Sections:
* vector palette: `(quat_off - vec_off)/12` × vec3 f32. Shared by translations and scales.
* quat palette: `(jointhash_off - quat_off)/6` × 48-bit quantized quaternion (§5.4).
* joint hashes: `(frames_off - jointhash_off)/4` × u32. This is the track order.
* frames: `frame_count × track_count × { u16 translation_idx; u16 scale_idx; u16 rotation_idx }`. Frame-major, then track.

Values: `fps = 1/frame_duration`. LTK uses `duration = frame_count · frame_duration`. Frame i is at `t = i · frame_duration`.

Example: `attack1.anm` has 12 frames at 30 fps, 211 tracks, resource size 41768, offsets (25732, 0, 0, 64, 16000, 26576).

### 5.2 `r3d2anmd` v4

Same 64-byte header, but:
* There is no joint-hash section.
* The quat palette is `(frames_off - quat_off)/16` × 4×f32 (x, y, z, w).
* Frames are `frame_count × track_count × { u32 joint_hash; u16 t_idx; u16 s_idx; u16 r_idx; u16 pad }` (12 bytes).

LTK normalizes palette quaternions. [VERIFIED decode on `joke_loop.anm`.]

### 5.3 `r3d2anmd` v3 (legacy, 854 files in 16.20)

[SOURCE LTK `ReadLegacy`; VERIFIED on an Amumu file, parse consumed exactly 29468/29468 bytes]

```
char[8] "r3d2anmd"; u32 version = 3
u32 skeleton_id; i32 track_count; i32 frame_count; i32 fps     (fps is an int, e.g. 30, 31)
track_count × {
    char name[32]; u32 flags
    frame_count × { f32 quat[4] (x,y,z,w); f32 translation[3] }   # 28 B; no scale (use 1,1,1)
}
```

Track hash = ELF(lower(name)). Duration = frame_count / fps.

### 5.4 48-bit quantized quaternion ("smallest three")

[SOURCE LTK `QuantizedQuaternion.cs`; VERIFIED (unit norms, sane poses)]

```python
SQRT2, INV_SQRT2 = 1.41421356237, 0.70710678118
def decompress_quat(v0, v1, v2):                 # three little-endian u16 (6 bytes)
    bits = v0 | (v1 << 16) | (v2 << 32)
    max_index = (bits >> 45) & 3                 # which component was dropped (largest |.|, made positive)
    a = ((bits >> 30) & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    b = ((bits >> 15) & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    c = ( bits        & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    d = math.sqrt(max(0.0, 1.0 - (a*a + b*b + c*c)))
    return [(d,a,b,c), (a,d,b,c), (a,b,d,c), (a,b,c,d)][max_index]   # (x, y, z, w)
```

### 5.5 `r3d2canm` (compressed, v1; LTK accepts 1–3)

[SOURCE LTK `CompressedAnimationAsset.cs`; VERIFIED]

**Header (128 bytes):**

| Offset | Type | Field |
|---:|---|---|
| 0 | char[8] | `r3d2canm` |
| 8 | u32 | version (1) |
| 12 | u32 | resource size |
| 16 | u32 | format token |
| 20 | u32 | flags. **bit 2 (0x4) = UseKeyframeParametrization**. Bits 0/1/3/4/5 are unknown |
| 24 | i32 | joint count |
| 28 | i32 | key count. LTK calls this "frameCount"; it counts **key records, not frames** |
| 32 | i32 | jump cache count |
| 36 | f32 | duration (seconds) |
| 40 | f32 | fps (30) |
| 44 | 6×f32 | error metrics: (margin, discontinuity threshold) × rotation, translation, scale |
| 68 | 3×f32 | translation min |
| 80 | 3×f32 | translation max |
| 92 | 3×f32 | scale min |
| 104 | 3×f32 | scale max |
| 116 | i32 | keys (frames) offset (+12) |
| 120 | i32 | jump caches offset (+12) |
| 124 | i32 | joint name hashes offset (+12) |

**Key record (10 bytes)**, `key_count` of them, stored in evaluation order:

```
u16 time          # compressed time: t_sec = time / 65535 * duration
u16 joint_type    # joint index = joint_type & 0x3FFF ; transform type = joint_type >> 14 : 0 rotation, 1 translation, 2 scale
u16 value[3]      # rotation: 48-bit quat (§5.4); translation/scale: v = min + (max-min) * (value / 65535)
```

`joint index` indexes the joint-hash array (u32 × joint_count).

**Jump caches** let the game seek quickly; an offline converter does **not** need them.
* Layout: `jump_cache_count × joint_count × { u16 rot_keys[4]; u16 trans_keys[4]; u16 scale_keys[4] }` (24 B).
* If key_count > 0x10000 the indices are u32 (48 B). None were seen in 16.20.
* Cache `k` covers time `k · duration / jump_cache_count`. Its 4 entries per curve are key indices of the initial window P0..P3.

**Curve structure** [VERIFIED on Ahri, every curve of 3 files]:
* There are exactly `joint_count × 3` curves.
* Each curve's keys appear in increasing time.
* Each curve **starts with two keys at t=0 and ends with two keys at t=65535**, and has at least 4 keys.
* **Duplicate timestamps in the middle of a curve mark discontinuities**: a step change at that instant. This is inferred from the data and from the "discontinuity threshold" error metric.
* The global stream is ordered by the time of the key two positions earlier in its own curve (the time it becomes "P3"). This is what makes the game's streaming evaluator work.

**Evaluation.** This is a cubic Catmull-Rom with 4 keys P0..P3 such that `t1 <= t < t2`:

```python
def catmull_weights(t, ease_in, ease_out):            # LTK CurveSampler.CreateCatmullRomWeights
    m0 = (((2.0 - t) * t) - 1.0) * (t * ease_in)
    m1 = ((((2.0 - ease_out) * t) + (ease_out - 3.0)) * (t * t)) + 1.0
    m2 = ((((3.0 - ease_in * 2.0) + ((ease_in - 2.0) * t)) * t) + ease_in) * t
    m3 = ((t - 1.0) * t) * (t * ease_out)
    return m0, m1, m2, m3            # value = m0*P0 + m1*P1 + m2*P2 + m3*P3 (quats: then normalize)

EPS = 1e-6
if flags & 4:   # parametrized (non-uniform) Catmull-Rom
    td = t2 - t1
    amount = (time - t1) / (td + EPS)
    ease_in  = td / (t2 - t0 + EPS)
    ease_out = td / (t3 - t1 + EPS)
else:           # uniform
    amount = (time - t1) / (t2 - t1)  (0 if t2 == t1)
    ease_in = ease_out = 0.5
```

This equals a cubic Hermite with tangents `T1 = ease_in·(P2−P0)` and `T2 = ease_out·(P3−P1)`.

**Simple offline decoder (recommended; `CompressedAnm.curves()` + `evaluate(t)` in the Appendix `lolanim.py`)** [VERIFIED equivalent to the LTK port]:

1. Group key records by `(joint, type)`, keeping stream order. That gives each curve's key list.
2. Decode the values and **align quaternion signs sequentially**: `if dot(q[i], q[i-1]) < 0: q[i] = -q[i]`.
3. To sample at compressed time `ct`:
   * Find the last index `i` with `key[i].t <= ct`, clamped to `n-2`.
   * The window is `key[max(i-1,0)], key[i], key[i+1], key[min(i+2,n-1)]`.
   * Apply the formula above.

The faithful LTK hot-frame/jump-cache evaluator was ported as well (`lolanim.py: evaluate_ltk`):
* Translation and scale match the simple decoder **exactly** (max diff 2e-8 over 61–121 samples on 4 animations).
* Rotations differ by up to 0.07 because LTK sign-aligns only P1 and P2 to P0, not P3. When P3 is also aligned, the two evaluators agree to 1e-9.
* The game's exact handling of P3 is **[UNCERTAIN]**. Sequential alignment is the mathematically correct choice and the one to use.

**Exact glTF export alternative** [VERIFIED numerically, max error 5e-7]:
* A parametrized curve maps exactly onto glTF `CUBICSPLINE`, using per-key tangent `(P[k+1]-P[k-1]) / (t[k+1]-t[k-1])` in units per second, the same for the in- and out-tangent.
* Uniform curves can use separate in- and out-tangents: `0.5·(P[k+1]-P[k-1]) / segment_length`. This is derived algebraically and was not tested numerically.
* Duplicate timestamps (discontinuities) violate glTF's strictly-increasing rule, so nudge them by about 1e-4 s.
* Resampling is simpler, and Godot bakes cubic splines at import anyway.

**Recommended glTF approach:** resample every animation at its fps (30) with LINEAR interpolation.
* Times: `i/fps` for i in `0..round(duration·fps)`. Include the endpoint `t = duration` so loops close.
* Convert seconds to compressed time with `ct = int(t / duration * 65535)`, as LTK does.
* lol2gltf samples `int(fps·duration)` frames and drops the endpoint.

**LTK bugs to avoid:**
* `DecompressTime(u16, duration)` performs integer division (`compressedTime / ushort.MaxValue`) and always returns 0 for times below the max.
* The uniform path divides by zero when `t2 == t1`.

Ahri sample: `attack1_toidle.anm` is r3d2canm v1, flags 0x7, 211 joints, 10703 keys, 11 jump caches, 2.6667 s at 30 fps; translation min (−56.5, −64.7, −35.1), max (81.0, 250.0, 154.6); scale min = max = (1, 1, 1). Uniform (flags 0x3) Aatrox clip: the vector channels of both evaluators match exactly.

---

## 6. Textures: TEX (`TEX\0`) and DDS

### 6.1 TEX header (12 bytes)

[SOURCE LTK `Texture.cs`, pyRitoFile `tex.py`; VERIFIED]

| Offset | Type | Field |
|---:|---|---|
| 0 | char[4] | `"TEX\0"` (u32 `0x00584554`) |
| 4 | u16 | width |
| 6 | u16 | height |
| 8 | u8 | unknown, always 1 |
| 9 | u8 | format (table below) |
| 10 | u8 | resource type: 0 = 2D (always); per LTK 1 cube, 2 surface, 3 volume |
| 11 | u8 | flags: bit 0 = has mipmaps |
| 12 | … | pixel data |

| Format | Meaning | Block size | Seen in 16.20 champs |
|---:|---|---|---|
| 1 | ETC1 | 8 B / 4×4 | – |
| 2, 3 | ETC2 / ETC2_EAC | 16 B / 4×4 | – |
| 10, 11 | BC1 / DXT1 | 8 B / 4×4 | 10: 118404 |
| 12 | BC3 / DXT5 | 16 B / 4×4 | 239047 |
| 13 | BC7 (per LTK) | 16 B / 4×4 | – |
| 14 | BC5 (per LTK) | 16 B / 4×4 | 9 (Bard; decodes plausibly) |
| 20 | BGRA8 | 4 B / pixel | 1 (Swain) |

**Mip order** [VERIFIED: `12 + Σ mip sizes == file size` for 4397/4397 Ahri textures]:
* Mips are stored **smallest first**, so the full-resolution image is the **last** `ceil(w/4)·ceil(h/4)·block_bytes` bytes of the file.
* Mip count = `floor(log2(max(w,h))) + 1` when flags bit 0 is set, otherwise 1.

### 6.2 Converting to PNG in Python

There is no need to wrap TEX in a DDS header: Pillow has a BCn decoder.

```python
from PIL import Image
w, h, fmt, flags = ...                       # header
n = {10: 1, 11: 1, 12: 3, 13: 7, 14: 5}[fmt]
blob = data[len(data) - ((w + 3)//4) * ((h + 3)//4) * (8 if n == 1 else 16):]   # top mip = tail of file
mode = {4: "L", 5: "RGB"}.get(n, "RGBA")    # Pillow requires L for BC4 and RGB for BC5
img = Image.frombuffer(mode, (w, h), blob, "bcn", n, "")
# BGRA8 (fmt 20): Image.frombuffer("RGBA", (w, h), blob, "raw", "BGRA", 0, 1)
img.save("out.png")
```

[VERIFIED: `ahri_base_tx_cm.tex` (BC3, 1024², mips) decodes to the correct, upright Ahri atlas, which also confirms the UV convention.]

**DDS:** use `Image.open(io.BytesIO(dds_bytes))`. DXT1/3/5 occur in champion WADs.

**ETC formats:** Pillow cannot decode them. They are mobile-only and absent from the PC client.

**Alpha:**
* BC3 diffuse textures carry alpha. Some materials use it for cutout or transparency (hair, tails).
* In glTF set `alphaMode: MASK` (cutoff about 0.3–0.5) for submeshes whose texture has meaningful alpha. Otherwise leave it OPAQUE.
* **[UNCERTAIN]** The bin's `techniques[].passes[].blendEnable` and alpha-test switches tell you which to use; heuristics are acceptable.
* Many champion `_TX_CM` textures use alpha for other purposes (masks). If transparency looks wrong, force OPAQUE.

---

## 7. Coordinate system, units, and glTF/Godot mapping

### 7.1 Evidence for handedness

[VERIFIED from Ahri's bind pose; global joint positions in model space]

```
L_Hip (-9.14, 119.05, -0.16)   R_Hip (9.14, 119.05, -0.16)
L_Eye (-3.05, 185.72,  6.59)   R_Eye (3.05, 185.72,  6.59)
L_Hand(-49.45,121.40, -3.60)   R_Hand(49.45,121.40, -3.60)   Weapon (51.31, 115.44, -2.44)
Main_Tail1 (0.00, 117.73, -14.72)        # tails behind (-Z), eyes in front (+Z) → model faces +Z
```

* The model faces **+Z**, with Y up, and the character's **left side is at −X**.
* Read as a right-handed system (glTF/Godot), that is a **mirror image**: a real person facing +Z in a right-handed Y-up frame has their left at +X. glTF says "front faces +Z", which puts the asset's left at +X and its right at −X.
* So League model data is **left-handed** (D3D convention). It probably also matches the world layout (Y up; X and Z span the map; the default camera looks from low Z toward +Z with +X to screen-right), but that part is **[UNCERTAIN]** because no map was rendered.
* It also agrees with LeagueToolkit's map exporter, which by default puts `scale(-1, 1, 1)` on the map root (`FlipAcrossX = true`).
* **lol2gltf's skinned-mesh export does not flip.** Its champion .glb files are therefore mirrored. The weapon or orb ends up in the wrong hand. It also emits double-sided unlit materials.

### 7.2 Winding

[VERIFIED] For 21630/21630 non-degenerate Ahri triangles, `dot(cross(v1−v0, v2−v0), vertex normal) > 0`. That means the raw indices are CCW-front in a right-handed reading, which is D3D's CW-front in left-handed space.

Mirroring one axis reverses orientation, so **after negating X you must swap two indices per triangle** (`(i0, i2, i1)`). If you skip both the mirror and the swap, winding is fine but the model is mirrored.

### 7.3 Conversion recipe (bake into data; do not use negative node scale)

Let `S` be the unit scale (recommended `0.01`: League units ≈ cm → meters).

| Data | League → glTF |
|---|---|
| position | `(-x, y, z) · S` |
| normal | `(-nx, ny, nz)` |
| tangent (vtype 2) | `(-tx, ty, tz, -tw)` |
| triangle | `(i0, i1, i2) → (i0, i2, i1)` |
| uv | unchanged |
| vertex color | BGRA u8 → RGBA (COLOR_0, normalized UNSIGNED_BYTE VEC4) |
| joint local T | `(-tx, ty, tz) · S` |
| joint local R | `(qx, -qy, -qz, qw)` |
| joint local S | unchanged |
| inverse bind | from the ibind TRS with the same T and R rules, then `T·R·S` (written **column-major** into the accessor) |
| anim T / R / S | same as joint local T / R / S |

* These rules are conjugation by `M = diag(-1, 1, 1)`. A general matrix X becomes `M·X·M`, which for a 4×4 means negating elements [0][1], [0][2], [0][3], [1][0], [2][0], [3][0].
* [VERIFIED] The mirrored skeleton still satisfies `G·IB ≈ I` (same 0.0033 drift). Mirrored `L_Hip` sits at (+9.14, 119.05, −0.16), i.e. asset-left = +X and front = +Z, which is exactly the glTF and Godot convention (Godot 4: `Vector3.MODEL_FRONT = +Z`).
* If you also convert gameplay coordinates from League data (turret or spawn positions from map bins), apply the same rule: `x_godot = -x_lol · S`, `z_godot = z_lol · S`.

### 7.4 glTF skin construction

* Make one glTF node per SKL joint, with the hierarchy taken from `parent`. Put all roots (Ahri has 2) under a single armature node.
* List **all** joints in `skin.joints` in SKL order. Then `JOINTS_0[v][k] = skl.influences[skn_joint_byte]`, which is a joint id equal to the skin.joints index.
  * Use `UNSIGNED_SHORT` for JOINTS_0 if any id is above 255 (some skeletons exceed 255 joints).
  * Set the joint to 0 where the weight is 0.
  * Keeping every joint, including buffbones and the weapon locator, in the skin lets Godot make them all `Skeleton3D` bones, which is useful for `BoneAttachment3D` and VFX sockets.
* WEIGHTS_0: float VEC4. Renormalize if the sum is not 1.
* One primitive per SKN range, one material per range (§2.4 resolution). Name the material after the range.
* Animations: one glTF animation per clip. For each joint with a track, write translation, rotation and scale channels. Keep quaternion continuity (sign-align consecutive samples).
* Godot import notes:
  * Godot 4 imports glTF skins as `Skeleton3D` and animations into an `AnimationPlayer`. Bone names must be unique; SKL names are.
  * If you prefer not to bake the scale, keep League units and set the import option `nodes/root_scale = 0.01`. Baking (S = 0.01 in data) is cleaner for physics and navigation.
  * The `Root` joint carries a 180° Y rotation in bind pose. That is expected; do not "fix" it.

---

## 8. Map geometry (`.mapgeo`, magic `OEGM`): Howling Abyss

[SOURCE LTK `EnvironmentAsset*.cs`; VERIFIED parse of Map12 `base` (v17) and `jade` (v18)]

### 8.1 Files

| File | Role |
|---|---|
| `data/maps/shipping/map12/map12.bin` | Lists map geometry variants as strings `Maps/MapGeometry/Map12/<Variant>` |
| `data/maps/mapgeometry/map12/<variant>.mapgeo` | The geometry |
| `data/maps/mapgeometry/map12/<variant>.materials.bin` | `StaticMaterialDef`s keyed by `fnv1a(material name)` |

Variants in 16.20: `base` (v17, 21.3 MB), `bilgewater` (v17), `bloom` (v17), `crepe` (v17), `jade` (v18). `base` is the classic Howling Abyss.

### 8.2 Layout

LTK supports versions 5–18; the rules below are for 17/18.

```
"OEGM" i32 version
if v < 7: u8 separate_point_lights
sampler defs: v>=17: i32 n × { i32 index; i32 len + chars }   (base: (0,'BAKED_DIFFUSE_TEXTURE'), (1,'BAKED_DIFFUSE_TEXTURE_ALPHA'))
              v9..16: 1–2 sized strings
u32 vertex_decl_count × { u32 usage; u32 elem_count; 15 × { u32 elem_name; u32 elem_format } }   # always 15 slots on disk, first elem_count valid
u32 vertex_buffer_count × { [v>=13: u8 visibility] u32 size; bytes }
u32 index_buffer_count  × { [v>=13: u8 visibility] i32 size; u16 indices }
u32 mesh_count × mesh
(then bucketed scene graph(s) and planar reflectors; not needed for rendering)

mesh:
  [v<=11: sized string name]
  i32 vertex_count; u32 stream_count; i32 first_vertex_decl_id
  stream_count × i32 vertex_buffer_id        # stream k uses vertex_decls[first_vertex_decl_id + k]
  u32 index_count; i32 index_buffer_id
  [v>=13 u8 visibility_layers] [v>=18 u32 region_hash] [v>=15 u32 visibility_controller_hash]
  u32 submesh_count × { u32 hash; i32 len + material name; i32 start_index; i32 index_count; i32 min_vertex; i32 max_vertex }
  [v!=5 u8 disable_backface_culling]
  f32 bbox[6]; f32 transform[16] (row-major); u8 quality_filter
  [v7..12 u8 visibility] [v11..13 u8 render_flags] [v>=14 u8 layer_transition; v<16 u8 / v>=16 u16 render_flags]
  v>=9: baked_light {i32 len + texture path; vec2 scale; vec2 bias}; stationary_light {same}
  v12..16: baked_paint {same}
  v>=17: i32 n × { i32 index; i32 len + texture }; vec2 baked_paint_scale; vec2 baked_paint_bias
```

**Element names:**

| Id | Element |
|---:|---|
| 0 | Position |
| 1 | BlendWeight |
| 2 | Normal |
| 3 | FogCoordinate |
| 4 | PrimaryColor |
| 5 | SecondaryColor |
| 6 | BlendIndex |
| 7–14 | Texcoord0–7 |

**Element formats:**

| Id | Format | Bytes |
|---:|---|---:|
| 0 | X_Float32 | 4 |
| 1 | XY_Float32 | 8 |
| 2 | XYZ_Float32 | 12 |
| 3 | XYZW_Float32 | 16 |
| 4 | BGRA_Packed8888 | 4 |
| 5 | ZYXW_Packed8888 | 4 |
| 6 | RGBA_Packed8888 | 4 |
| 7 | XY_Packed1616 | 4 |
| 8 | XYZ_Packed161616 | 8 |
| 9 | XYZW_Packed16161616 | 8 |

[VERIFIED] **The v18 "Packed16" formats are IEEE half floats**: decoded `jade` normals have |n| = 1.000. Use `struct.unpack("<3e")`.

### 8.3 Map12 `base` statistics

[VERIFIED]
* 342 meshes, 391 vertex buffers, 200 index buffers, 8 vertex declarations.
* **451,719 vertices, 255,478 triangles.**
* 50 distinct materials. All resolve in `base.materials.bin` (class `StaticMaterialDef`, sampler `DiffuseTexture`, `texturePath` is a `file` key), and all 50 textures are present in `Map12.wad.client`.
* All transforms are identity (positions are already world-space). Visibility is 255 (all layers) and quality is 31 for every mesh.
* World bounds include a huge sky/backdrop: x −33156..39211, y −35955..1625, z −6369..46703. The playable lane is roughly 0..13000 in x/z.

**Vertex streams:**
* Meshes have 1 or 2 streams. With 2 streams, stream 0 holds position (+normal) and is unique to the mesh; stream 1 holds Texcoord0 + Texcoord7.
* Instanced copies share stream 1 and the index buffer, with the same vertex count and topology. 46 vertex buffers and 40 index buffers are shared.
* `mesh.index_count` equals the full index buffer length in every case, and the submesh ranges tile it. Indices are local to the mesh's vertex streams (0..vertex_count−1).

**UV channels and lighting:**
* Texcoord0 = material UV.
* **Texcoord7 = lightmap UV.** Final lightmap UV = `uv7 · baked_light.scale + baked_light.bias`, sampling `baked_light.texture`. Base has 17 lightmap TEX files, all present, e.g. `ASSETS/Maps/Lightmaps/Maps/MapGeometry/Map12/Base/10.tex`. The baked lightmap is what gives the map its look.

### 8.4 Practicality

Exporting the Howling Abyss environment is **very practical**:
* about 450k vertices and 255k triangles, which is fine for Godot as one or a few MeshInstances merged per material;
* 50 diffuse textures plus 17 lightmaps;
* static geometry with no skinning.

Recommended steps:
1. Mirror X and reverse winding, the same as champions. Map winding was not separately tested **[UNCERTAIN]**, but should follow the same convention. Verify visually and flip if back-faces show.
2. Scale by 0.01.
3. Drop or keep the skybox meshes using the bounding boxes.
4. Use the lightmap as a second UV set (TEXCOORD_1). In Godot, multiply it in a ShaderMaterial or bake it into the albedo.

Animated props (Poros, the bridge, braziers) are separate characters and particles in the map bins. They are not part of mapgeo.

---

## 9. Probes run and their results

All scripts are in the scratchpad `formats\` folder. Run them from that folder with `python <script>`.

| Script | What it verified |
|---|---|
| `probe_a_wad.py` | WAD 3.4, 6078 entries; histogram none 28 / zstd 2406 / subchunked 3644; subchunk TOC found (9195 records); xxh3 checksum rule; all entries decompress; hash presence table (§1.4) |
| `probe_b_skn_skl.py` | Ahri SKN/SKL found by computed hash; counts and ranges (§3.4); winding test; SKL header/joints, ELF hashes, index table, influences, bind consistency |
| `dump_bin.py <wad> <bin> --resolve` | Full ritobin-like text dump with CDragon names (`skin0_dump.txt`, `anim0_dump.txt`) |
| `probe_cd_bins.py [Champ] [skin]` | (c) ASCII-scan vs structured skin data; texture and material resolution; animation-graph link == fnv1a(path). (d) 72 clips → 55 .anm, all present, names via hash list, anm version census |
| `probe_e_anm.py` | Compressed and uncompressed decode; joint coverage; curve structure; LTK-vs-simple cross-check; global joint positions (handedness) |
| `probe_f_tex.py` | TEX census, mip-size rule, PNG decode (`out\ahri_base_tx_cm.png`) |
| `probe_g_mapgeo.py [variant]` | Map12 mapgeo parse, statistics, material → texture resolution |
| `probe_h_skinning.py` | Skinning chain (influences → joints → ibind → anim pose) produces sane posed bboxes; mirrored-skeleton check |
| `probe_i_variants.py` | SKN 0.1/1.1/2.1, ANM v3, uniform canm, TEX BC5/BGRA8 |
| `census_all.py` | Version census over all 174 champion WADs (§0), 167 s |
| `stream_game_hashes.py <substr...>` | Streams CDragon `hashes.game.txt` and keeps matching lines (`game_hashes_filtered.txt`) |

Key outputs (abridged):

```
(a) WAD version 3.4, entries=6078 | type 0 (none): 28 | type 3 (zstd): 2406 | type 4 (zstd-subchunked): 3644
    subchunk counts: 3 → 1907 entries, 2 → 1737 | toc data/final/champions/ahri.wad.subchunktoc 9195 records
    entry checksum == xxh3_64(stored bytes): 300 ok / 0 mismatch | decompress errors: 0
(b) SKN v4.1 vertex_type=0 vertex_size=52 vertices=13780 indices=65034 | weight sums 1.0000/1.0000
    uv range u[0.003,0.997] v[0.002,0.999] | winding: dot(cross,normal)>0 for 21630 tris, <0 for 0
    SKL modern joints=211 influences=177 | ids==index True | parent<child True | name_hash==elf True
    max SKN joint byte = 176 (< 177) | max |G*IB - I| = 0.00334
(c) skeleton/simpleSkin strings present in WAD: True/True
    texture file 12cf9c27d09be6c5 = assets/characters/ahri/skins/base/ahri_base_tx_cm.tex (TEX in WAD)
    override 'Tails' → MAT_Tails_inst: Diffuse_Texture=ahri_base_tails_tx_cm.tex, Mask_Texture_red=...
    animationGraphData link 0e4757c8 == fnv1a('Characters/Ahri/Animations/Skin0') → True
(d) 72 clips {Atomic 55, Sequencer 8, ConditionBool 5, ConditionFloat 2, Selector 2}; .anm present 55/55
    e.g. clip Attack1 → .../animations/attack1.anm ; clip 1efabc75 → .../animations/idle1.anm ; Channel → channel_loop.anm
    sample attack1.anm: magic=b'r3d2anmd' version=5 ; whole-WAD: anmd v5 352, canm v1 374, anmd v4 5
(e) attack1_toidle.anm r3d2canm v1 flags=0x7 joints=211 keys=10703 jumpcaches=11 duration=2.6667 fps=30
    curves=633, first key t=0: 633, last key 65535: 633, monotonic, keys/curve min/median/max 4/4/89
    LTK vs simple: vectors 2e-8; quats 0.069 (LTK, no P3 alignment) → 6.6e-11 with P3 aligned
(h) bind-pose skinning max delta 0.64 units; idle1 frame0 bbox ((-139.5,0,-135.2),(116.4,201.7,43.1));
    run frame0 ((-29.6,38.3,-149.1),(62.4,224.3,84.0)); mirrored L_Hip = (+9.14, 119.05, -0.16)
(i) SKN 0.1 Anivia (226 v), 1.1 Bard, 2.1 Amumu (12 trailing bytes): all parse; ANM v3 Amumu 31 fps parses exactly;
    canm flags 0x3 Aatrox uniform: vectors identical; TEX fmt 14 (BC5) → RGB, fmt 20 → RGBA
```

---

## 10. Things that did not work, and open questions

* **`assets/characters/ahri/skins/base/ahri.skn` / `.skl` do not exist** in the current WAD. The real files are `ahri_base.skn` / `ahri_base.skl`, named by `skinMeshProperties`. Always read the path from the skin bin.
* **ASCII scanning cannot find textures or animations** in 16.20; they are `file` (u64) hashes. Parse the bin.
* Clip names are FNV hashes and most cannot be recovered offline. Use the CDragon hash list for .anm basenames, or hex names.
* CommunityDragon returns **HTTP 403 without a User-Agent header**.
* Pillow's BC5 decoder requires mode `"RGB"`; asking for `"RGBA"` raises `ValueError: bad image mode`.
* The LTK uniform Catmull-Rom path and `DecompressTime` have arithmetic bugs (§5.5). LTK reads WAD 3.4 byte 21 as a bool (§1.2).
* **[UNCERTAIN]** The game's quaternion sign handling for P3 in compressed animation evaluation. Up to 0.07 quaternion component difference versus LTK; sequential alignment is recommended.
* **[UNCERTAIN]** Meaning of canm flag bits other than 0x4, SKN v4 `flags`, SKL `flags` and joint `flags` (all 0 in Ahri), and the TEX unknown byte (always 1).
* **[UNCERTAIN]** TEX formats 13 (BC7) and 1–3 (ETC) are not present in PC champion WADs, so they were not tested.
* **[UNCERTAIN]** `skinScale` semantics, and when to use alpha blend versus alpha test per material (needs a heuristic or shader-name mapping).
* Legacy `r3d2sklt`, WAD v1/v2, gzip and redirect entries, and legacy bin type ids were not tested because they are absent from 16.20 data. They are documented from source.
* **[UNCERTAIN]** Map winding and orientation after mirroring were not rendered.

---

## Appendix: verified reference modules (verbatim copies of the probe library)

These are the exact modules the probes above ran against. They are pure Python (struct, zstandard, xxhash, Pillow) and are not optimized: SKN vertex parsing goes vertex by vertex. Use `numpy.frombuffer` with a structured dtype for speed in production.


### `lolwad.py`: WAD reader (all compression types, subchunk TOC, path hashing)

```python
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
```

### `lolbin.py`: PROP/PTCH bin reader (current + legacy type ids)

```python
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
```

### `lolmesh.py`: SKN + SKL readers, ELF hash, TRS helpers

```python
"""SKN (SimpleSkin) and SKL (RigResource / legacy r3d2sklt) parsers. Pure Python (struct only)."""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field


def elf_hash(name: str) -> int:
    """Joint-name hash used by SKL joint index table and ANM tracks (ELF hash of lower-cased name)."""
    h = 0
    for c in name.lower().encode("ascii"):
        h = ((h << 4) + c) & 0xFFFFFFFF
        high = h & 0xF0000000
        if high:
            h ^= high >> 24
        h &= ~high & 0xFFFFFFFF
    return h


# ----------------------------------------------------------------------------- SKN
@dataclass
class SknRange:
    material: str
    start_vertex: int
    vertex_count: int
    start_index: int
    index_count: int


@dataclass
class Skn:
    major: int
    minor: int
    flags: int
    ranges: list
    vertex_type: int          # 0 basic(52B) 1 color(56B) 2 tangent(72B)
    vertex_size: int
    bbox: tuple | None
    bsphere: tuple | None
    indices: list             # flat u16 list
    positions: list
    joints: list              # 4 x u8, indices INTO SKL influences table
    weights: list             # 4 x f32
    normals: list
    uvs: list
    colors: list | None       # 4 x u8 (B,G,R,A in memory)
    tangents: list | None     # 4 x f32


def read_skn(d: bytes) -> Skn:
    magic, major, minor = struct.unpack_from("<IHH", d, 0)
    if magic != 0x00112233:
        raise ValueError("bad SKN magic")
    p = 8
    flags = 0
    vtype, vsize = 0, 52
    bbox = bsphere = None
    if major == 0:
        icount, vcount = struct.unpack_from("<II", d, p); p += 8
        ranges = [SknRange("Base", 0, vcount, 0, icount)]
    else:
        (nr,) = struct.unpack_from("<I", d, p); p += 4
        ranges = []
        for _ in range(nr):
            name = d[p:p + 64].split(b"\0", 1)[0].decode("ascii", "replace")
            sv, vc, si, ic = struct.unpack_from("<4I", d, p + 64)
            ranges.append(SknRange(name, sv, vc, si, ic))
            p += 80
        if major == 4:
            (flags,) = struct.unpack_from("<I", d, p); p += 4
        icount, vcount = struct.unpack_from("<II", d, p); p += 8
        if major == 4:
            vsize, vtype = struct.unpack_from("<II", d, p); p += 8
            bbox = (struct.unpack_from("<3f", d, p), struct.unpack_from("<3f", d, p + 12)); p += 24
            bsphere = (struct.unpack_from("<3f", d, p), struct.unpack_from("<f", d, p + 12)[0]); p += 16
    indices = list(struct.unpack_from(f"<{icount}H", d, p)); p += 2 * icount
    pos, jnt, wgt, nrm, uv, col, tan = [], [], [], [], [], [], []
    for i in range(vcount):
        b = p + i * vsize
        pos.append(struct.unpack_from("<3f", d, b))
        jnt.append(struct.unpack_from("<4B", d, b + 12))
        wgt.append(struct.unpack_from("<4f", d, b + 16))
        nrm.append(struct.unpack_from("<3f", d, b + 32))
        uv.append(struct.unpack_from("<2f", d, b + 44))
        if vtype >= 1:
            col.append(struct.unpack_from("<4B", d, b + 52))
        if vtype == 2:
            tan.append(struct.unpack_from("<4f", d, b + 56))
    return Skn(major, minor, flags, ranges, vtype, vsize, bbox, bsphere, indices,
               pos, jnt, wgt, nrm, uv, col or None, tan or None)


# ----------------------------------------------------------------------------- SKL
@dataclass
class Joint:
    name: str
    flags: int
    id: int
    parent: int
    radius: float
    name_hash: int
    local_t: tuple
    local_s: tuple
    local_r: tuple            # quaternion x,y,z,w
    ibind_t: tuple
    ibind_s: tuple
    ibind_r: tuple


@dataclass
class Skl:
    modern: bool
    flags: int
    name: str
    asset_name: str
    joints: list
    influences: list          # influence slot -> joint id (SKN vertex joint byte indexes this)
    hash_to_id: dict = field(default_factory=dict)


def _cstr(d, p):
    e = d.index(b"\0", p)
    return d[p:e].decode("ascii", "replace")


def read_skl(d: bytes) -> Skl:
    if struct.unpack_from("<I", d, 4)[0] == 0x22FD4FC3:
        file_size, token, version, flags, jcount, icount = struct.unpack_from("<IIIHHI", d, 0)
        (j_off, jidx_off, inf_off, name_off, asset_off, names_off) = struct.unpack_from("<6i", d, 20)
        joints = []
        for i in range(jcount):
            b = j_off + i * 100
            fl, jid, par, _pad, nh, rad = struct.unpack_from("<HhhhIf", d, b)
            lt = struct.unpack_from("<3f", d, b + 16); ls = struct.unpack_from("<3f", d, b + 28)
            lr = struct.unpack_from("<4f", d, b + 40)
            it = struct.unpack_from("<3f", d, b + 56); is_ = struct.unpack_from("<3f", d, b + 68)
            ir = struct.unpack_from("<4f", d, b + 80)
            (noff,) = struct.unpack_from("<i", d, b + 96)
            name = _cstr(d, b + 96 + noff)      # relative to the position of the offset field itself
            joints.append(Joint(name, fl, jid, par, rad, nh, lt, ls, lr, it, is_, ir))
        infl = list(struct.unpack_from(f"<{icount}h", d, inf_off)) if inf_off > 0 else []
        h2i = {}
        if jidx_off > 0:
            for i in range(jcount):
                jid, _pad, h = struct.unpack_from("<hHI", d, jidx_off + 8 * i)
                h2i[h] = jid
        name = _cstr(d, name_off) if name_off > 0 else ""
        asset = _cstr(d, asset_off) if asset_off > 0 else ""
        return Skl(True, flags, name, asset, joints, infl, h2i)
    # legacy r3d2sklt v1/v2: global 3x4 matrices
    if d[:8] != b"r3d2sklt":
        raise ValueError("bad SKL")
    version, skel_id, jcount = struct.unpack_from("<III", d, 8)
    p = 20
    raw = []
    for i in range(jcount):
        name = d[p:p + 32].split(b"\0", 1)[0].decode("ascii", "replace")
        par, rad = struct.unpack_from("<if", d, p + 32)
        m = struct.unpack_from("<12f", d, p + 40)   # stored 3 rows x 4 cols (row-major, translation in col 3)
        raw.append((name, par, rad, m)); p += 88
    if version == 2:
        (n,) = struct.unpack_from("<I", d, p); p += 4
        infl = list(struct.unpack_from(f"<{n}I", d, p))
    else:
        infl = list(range(jcount))
    joints = [Joint(n, 0, i, par, rad, elf_hash(n), None, None, None, None, None, None)
              for i, (n, par, rad, m) in enumerate(raw)]
    # (Converting global matrices -> local TRS is left to the caller; see spec.)
    s = Skl(False, 0, "", "", joints, infl, {j.name_hash: j.id for j in joints})
    s.legacy_global_matrices = [m for (_, _, _, m) in raw]
    return s


# ----------------------------------------------------------------------------- helpers
def quat_to_mat3(q):
    x, y, z, w = q
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


def trs_to_mat4(t, r, s):
    """Column-vector convention: M = T * R * S (what glTF uses)."""
    m = quat_to_mat3(r)
    return [[m[0][0] * s[0], m[0][1] * s[1], m[0][2] * s[2], t[0]],
            [m[1][0] * s[0], m[1][1] * s[1], m[1][2] * s[2], t[1]],
            [m[2][0] * s[0], m[2][1] * s[1], m[2][2] * s[2], t[2]],
            [0.0, 0.0, 0.0, 1.0]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
```

### `lolanim.py`: ANM readers: r3d2anmd v3/v4/v5, r3d2canm (recommended evaluate() + faithful LTK port evaluate_ltk())

```python
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
```

### `lolfmt_tex.py`: TEX/DDS to Pillow image

```python
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
```

### `lolmapgeo.py`: mapgeo reader (v5-18, mesh table only)

```python
"""Map geometry (.mapgeo, magic 'OEGM') reader, versions 5..18 (layout ported from LeagueToolkit EnvironmentAsset).
Stops after the mesh table (bucketed scene graph / planar reflectors are not needed for rendering)."""
from __future__ import annotations

import struct
from dataclasses import dataclass, field

ELEM_NAMES = ["Position", "BlendWeight", "Normal", "FogCoordinate", "PrimaryColor", "SecondaryColor",
              "BlendIndex", "Texcoord0", "Texcoord1", "Texcoord2", "Texcoord3", "Texcoord4", "Texcoord5",
              "Texcoord6", "Texcoord7", "Tangent"]
FMT = {0: ("X_Float32", 4), 1: ("XY_Float32", 8), 2: ("XYZ_Float32", 12), 3: ("XYZW_Float32", 16),
       4: ("BGRA_Packed8888", 4), 5: ("ZYXW_Packed8888", 4), 6: ("RGBA_Packed8888", 4),
       7: ("XY_Packed1616", 4), 8: ("XYZ_Packed161616", 8), 9: ("XYZW_Packed16161616", 8),
       10: ("XY_Packed88", 2), 11: ("XYZ_Packed888", 3), 12: ("XYZW_Packed8888", 4)}


class R:
    def __init__(self, d):
        self.d, self.p = d, 0

    def u(self, fmt):
        v = struct.unpack_from(fmt, self.d, self.p); self.p += struct.calcsize(fmt)
        return v if len(v) > 1 else v[0]

    def sstr(self):
        n = self.u("<i"); s = self.d[self.p:self.p + n].decode("utf-8", "replace"); self.p += n
        return s


@dataclass
class Submesh:
    hash: int
    material: str
    start_index: int
    index_count: int
    min_vertex: int
    max_vertex: int


@dataclass
class Mesh:
    name: str
    vertex_count: int
    vertex_decl_id: int
    vertex_buffer_ids: list
    index_count: int
    index_buffer_id: int
    visibility: int
    submeshes: list
    disable_backface_culling: bool
    bbox: tuple
    transform: tuple            # 16 floats, row-major (row-vector convention, translation in last row)
    quality: int
    render_flags: int
    baked_light: tuple          # (texture, scale, bias)
    stationary_light: tuple
    texture_overrides: list = field(default_factory=list)


@dataclass
class MapGeo:
    version: int
    sampler_defs: list
    vertex_decls: list          # [(usage, [(elem_name, fmt), ...])]
    vertex_buffers: list        # [(visibility, offset, size)]
    index_buffers: list         # [(visibility, offset, size)]
    meshes: list


def read_mapgeo(d: bytes) -> MapGeo:
    r = R(d)
    assert r.d[:4] == b"OEGM"; r.p = 4
    v = r.u("<i")
    sep_point_lights = r.u("<?") if v < 7 else False
    samplers = []
    if v >= 17:
        for _ in range(r.u("<i")):
            samplers.append((r.u("<i"), r.sstr()))
    else:
        if v >= 9:
            samplers.append((0, r.sstr()))
        if v >= 11:
            samplers.append((1, r.sstr()))
    decls = []
    for _ in range(r.u("<I")):
        usage, n = r.u("<II")
        elems = [r.u("<II") for _ in range(n)]
        r.p += 8 * (15 - n)                       # always 15 element slots on disk
        decls.append((usage, elems))
    vbs = []
    for _ in range(r.u("<I")):
        vis = r.u("<B") if v >= 13 else 0xFF
        size = r.u("<I"); vbs.append((vis, r.p, size)); r.p += size
    ibs = []
    for _ in range(r.u("<I")):
        vis = r.u("<B") if v >= 13 else 0xFF
        size = r.u("<i"); ibs.append((vis, r.p, size)); r.p += size
    meshes = []
    for mi in range(r.u("<I")):
        name = r.sstr() if v <= 11 else f"MapGeo_Instance_{mi}"
        vcount, ndecl, decl_id = r.u("<iIi")
        vb_ids = [r.u("<i") for _ in range(ndecl)]
        icount, ib_id = r.u("<Ii")
        vis = 0xFF
        if v >= 13:
            vis = r.u("<B")
        if v >= 18:
            _region_hash = r.u("<I")
        if v >= 15:
            _vis_controller = r.u("<I")
        subs = []
        for _ in range(r.u("<I")):
            h = r.u("<I"); mat = r.sstr(); si, ic, mnv, mxv = r.u("<4i")
            subs.append(Submesh(h, mat, si, ic, mnv, mxv))
        dbc = r.u("<?") if v != 5 else False
        bbox = (r.u("<3f"), r.u("<3f"))
        xf = r.u("<16f")
        quality = r.u("<B")
        if 7 <= v <= 12:
            vis = r.u("<B")
        rflags = 0
        if 11 <= v < 14:
            rflags = r.u("<B")
        elif v >= 14:
            _layer_transition = r.u("<B")
            rflags = r.u("<B") if v < 16 else r.u("<H")
        if sep_point_lights and v < 7:
            r.u("<3f")
        if v < 9:
            r.p += 9 * 12                          # spherical harmonics
            baked = (r.sstr(), r.u("<2f"), r.u("<2f")); stat = None; tov = []
        else:
            baked = (r.sstr(), r.u("<2f"), r.u("<2f"))
            stat = (r.sstr(), r.u("<2f"), r.u("<2f"))
            tov = []
            if 12 <= v < 17:
                tov.append((0, r.sstr())); r.u("<2f"); r.u("<2f")
            if v >= 17:
                for _ in range(r.u("<i")):
                    tov.append((r.u("<i"), r.sstr()))
                r.u("<2f"); r.u("<2f")             # baked paint scale, bias
        meshes.append(Mesh(name, vcount, decl_id, vb_ids, icount, ib_id, vis, subs, dbc, bbox, xf, quality,
                           rflags, baked, stat, tov))
    return MapGeo(v, samplers, decls, vbs, ibs, meshes)


def mesh_vertex_layout(g: MapGeo, m: Mesh):
    """List of (buffer_id, stride, [(elem_name, fmt_name, offset)]) for the mesh's vertex streams."""
    out = []
    for i, vb in enumerate(m.vertex_buffer_ids):
        usage, elems = g.vertex_decls[m.vertex_decl_id + i]
        off = 0; lay = []
        for (en, ef) in elems:
            fname, sz = FMT[ef]
            lay.append((ELEM_NAMES[en], fname, off)); off += sz
        out.append((vb, off, lay))
    return out
```

### `probe_a_wad.py`: probe (a): WAD listing / compression histogram / hash checks

```python
"""Probe (a): open Ahri.wad.client, entry count, compression histogram, checksum check, hash check."""
import collections
import sys

import xxhash

from lolwad import COMP_NAMES, Wad, guess_kind, wad_path_hash

ROOT = r"D:\Riot Games\League of Legends\Game\DATA\FINAL"
path = sys.argv[1] if len(sys.argv) > 1 else ROOT + r"\Champions\Ahri.wad.client"

with Wad(path) as w:
    print(f"WAD version {w.major}.{w.minor}, entries={len(w.entries)}")
    hist = collections.Counter(e.type for e in w.entries.values())
    for t, n in sorted(hist.items()):
        print(f"  type {t} ({COMP_NAMES.get(t)}): {n}")
    sub = [e for e in w.entries.values() if e.type == 4]
    if sub:
        print("  subchunk counts (high nibble) histogram:", collections.Counter(e.subchunk_count for e in sub).most_common(8))
    print("subchunk toc:", getattr(w, "subchunk_toc_path", None), None if w.subchunk_toc is None else len(w.subchunk_toc) // 16, "records")

    # checksum = xxh3_64 of stored bytes?
    ok = bad = 0
    for e in list(w.entries.values())[:300]:
        raw = w.raw(e)
        if xxhash.xxh3_64_intdigest(raw) == e.checksum:
            ok += 1
        else:
            bad += 1
    print(f"entry checksum == xxh3_64(stored bytes): {ok} ok / {bad} mismatch (first 300)")

    # decompress everything, verify sizes, histogram file kinds
    kinds = collections.Counter()
    errors = 0
    for e in w.entries.values():
        try:
            d = w.read_entry(e)
        except Exception as ex:  # noqa
            errors += 1
            continue
        if d is None:
            kinds["<redirect>"] += 1
            continue
        if len(d) != e.size:
            errors += 1
        kinds[guess_kind(d)] += 1
    print("decompress errors/size mismatches:", errors)
    print("kinds:", dict(kinds.most_common()))

    for p in ["assets/characters/ahri/skins/base/ahri.skn",
              "ASSETS/Characters/Ahri/Skins/Base/Ahri.skn",
              "assets/characters/ahri/skins/base/ahri.skl",
              "data/characters/ahri/skins/skin0.bin",
              "data/characters/ahri/ahri.bin",
              "data/characters/ahri/animations/skin0.bin"]:
        print(f"  {wad_path_hash(p):016x}  present={w.has(p)}  {p}")
```

### `probe_b_skn_skl.py`: probe (b): SKN/SKL by computed hash, sanity checks, winding test

```python
"""Probe (b): find & decompress Ahri SKN/SKL by computed path hash, parse, sanity-check."""
import collections
import sys

from lolmesh import elf_hash, matmul, read_skl, read_skn, trs_to_mat4
from lolwad import Wad, wad_path_hash

ROOT = r"D:\Riot Games\League of Legends\Game\DATA\FINAL"
wad_path = sys.argv[1] if len(sys.argv) > 1 else ROOT + r"\Champions\Ahri.wad.client"
skn_path = sys.argv[2] if len(sys.argv) > 2 else "assets/characters/ahri/skins/base/ahri_base.skn"
skl_path = skn_path[:-4] + ".skl"

with Wad(wad_path) as w:
    for p in (skn_path, skl_path):
        e = w.entries.get(wad_path_hash(p))
        print(f"{p}: hash={wad_path_hash(p):016x} found={e is not None}",
              "" if e is None else f"comp={e.type} csize={e.compressed_size} size={e.size}")
    skn_d = w.get(skn_path)
    skl_d = w.get(skl_path)
    # version census over every SKN/SKL in the WAD
    vers = collections.Counter()
    for e in w.entries.values():
        d = w.read_entry(e)
        if d is None:
            continue
        if d[:4] == b"\x33\x22\x11\x00":
            import struct
            ma, mi = struct.unpack_from("<HH", d, 4)
            vt = struct.unpack_from("<I", d, 8 + 4 + 80 * struct.unpack_from("<I", d, 8)[0] + 4 + 8 + 4)[0] if ma == 4 else -1
            vers[f"skn {ma}.{mi} vtype={vt}"] += 1
        elif len(d) > 8 and d[4:8] == b"\xc3\x4f\xfd\x22":
            vers["skl modern(0x22FD4FC3) v" + str(int.from_bytes(d[8:12], "little"))] += 1
        elif d[:8] == b"r3d2sklt":
            vers["skl legacy r3d2sklt"] += 1
    print("version census:", dict(vers))

skn = read_skn(skn_d)
print(f"\nSKN v{skn.major}.{skn.minor} flags={skn.flags} vertex_type={skn.vertex_type} vertex_size={skn.vertex_size}")
print(f"  vertices={len(skn.positions)} indices={len(skn.indices)} triangles={len(skn.indices)//3}")
print(f"  bbox={skn.bbox} bsphere={skn.bsphere}")
for r in skn.ranges:
    sub = skn.indices[r.start_index:r.start_index + r.index_count]
    print(f"  range '{r.material}': v[{r.start_vertex}+{r.vertex_count}] i[{r.start_index}+{r.index_count}]"
          f" idx min/max={min(sub)}/{max(sub)} (absolute indices)")
ws = [sum(w4) for w4 in skn.weights]
print(f"  weight sums min/max: {min(ws):.4f}/{max(ws):.4f}")
us = [u for u, v in skn.uvs]; vs = [v for u, v in skn.uvs]
print(f"  uv range u[{min(us):.3f},{max(us):.3f}] v[{min(vs):.3f},{max(vs):.3f}]")
ys = [p[1] for p in skn.positions]
print(f"  height (Y) range: {min(ys):.1f} .. {max(ys):.1f}")
if skn.colors:
    print("  first colors:", skn.colors[:3])

# winding test: dot(cross(v1-v0, v2-v0), avg vertex normal)
pos, nrm, idx = skn.positions, skn.normals, skn.indices
pos_cnt = neg_cnt = 0
for t in range(0, len(idx), 3):
    a, b, c = pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]]
    e1 = [b[i] - a[i] for i in range(3)]; e2 = [c[i] - a[i] for i in range(3)]
    cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
    n = [nrm[idx[t]][i] + nrm[idx[t + 1]][i] + nrm[idx[t + 2]][i] for i in range(3)]
    dp = sum(cr[i] * n[i] for i in range(3))
    if dp > 0:
        pos_cnt += 1
    elif dp < 0:
        neg_cnt += 1
print(f"  winding: dot(cross,normal)>0 for {pos_cnt} tris, <0 for {neg_cnt} tris "
      f"=> {'CCW front (right-handed reading)' if pos_cnt > neg_cnt else 'CW front (right-handed reading)'}")

skl = read_skl(skl_d)
print(f"\nSKL modern={skl.modern} flags={skl.flags} name='{skl.name}' asset='{skl.asset_name}'")
print(f"  joints={len(skl.joints)} influences={len(skl.influences)}")
print("  first joints:")
for j in skl.joints[:6]:
    print(f"    id={j.id} parent={j.parent} name={j.name} hash={j.name_hash:08x} elf={elf_hash(j.name):08x} "
          f"T={tuple(round(x, 3) for x in j.local_t)} R={tuple(round(x, 4) for x in j.local_r)} S={tuple(round(x, 3) for x in j.local_s)}")
print("  ids == array index:", all(j.id == i for i, j in enumerate(skl.joints)))
print("  parent < child for all:", all(j.parent < j.id for j in skl.joints))
print("  name_hash == elf(lower(name)) for all:", all(j.name_hash == elf_hash(j.name) for j in skl.joints))
print("  joint-index table matches:", all(skl.hash_to_id.get(elf_hash(j.name)) == j.id for j in skl.joints))
mx = max(max(j4) for j4 in skn.joints)
print(f"  max SKN joint byte = {mx} (< influences {len(skl.influences)}: {mx < len(skl.influences)})")
print("  influences[:12] =", skl.influences[:12])

# bind pose consistency: global(local chain) * ibind ~= identity
glob = []
maxerr = 0.0
for j in skl.joints:
    L = trs_to_mat4(j.local_t, j.local_r, j.local_s)
    G = L if j.parent < 0 else matmul(glob[j.parent], L)
    glob.append(G)
    IB = trs_to_mat4(j.ibind_t, j.ibind_r, j.ibind_s)
    P = matmul(G, IB)
    for r in range(4):
        for c in range(4):
            maxerr = max(maxerr, abs(P[r][c] - (1.0 if r == c else 0.0)))
print(f"  max |Global(local chain) * TRS(ibind) - I| = {maxerr:.5f}  (ibind = T*R*S of inverse bind)")
```

### `probe_cd_bins.py`: probes (c)+(d): skin bin -> assets, animation graph -> .anm, ANM headers

```python
"""Probes (c) + (d):
 (c) skin bin -> mesh / skeleton / textures / material overrides / animation graph link
 (d) animation graph bin -> clip name hash -> .anm (file hash = WAD key), decode .anm headers

Optional: game_hashes_filtered.txt (lines '<xxh64 hex> <path>' from CommunityDragon hashes.game.txt)
          is used only to print human-readable names; lookups work without it.
"""
import collections
import os
import re
import struct
import sys

from lolbin import BinStruct, fnv1a32, read_bin, walk
from lolwad import Wad, guess_kind, wad_path_hash

ROOT = r"D:\Riot Games\League of Legends\Game\DATA\FINAL"
champ = sys.argv[1] if len(sys.argv) > 1 else "Ahri"
skin = int(sys.argv[2]) if len(sys.argv) > 2 else 0
wad_file = ROOT + rf"\Champions\{champ}.wad.client"

names = {}
hf = os.path.join(os.path.dirname(os.path.abspath(__file__)), "game_hashes_filtered.txt")
if os.path.exists(hf):
    with open(hf, encoding="utf-8") as f:
        for line in f:
            h, _, p = line.rstrip("\n").partition(" ")
            names[int(h, 16)] = p


def pname(h):
    return names.get(h, f"<unknown {h:016x}>")


H = fnv1a32
with Wad(wad_file) as w:
    skin_bin_path = f"data/characters/{champ.lower()}/skins/skin{skin}.bin"
    data = w.get(skin_bin_path)
    print(f"== (c) {skin_bin_path}: {len(data)} bytes, magic {data[:4]}")

    # Pragmatic approach: printable strings (bin strings are u16-length-prefixed, so do it properly)
    strs = []
    for m in re.finditer(rb"[ -~]{4,}", data):
        s = m.group().decode()
        start = m.start()
        # a real bin string has its u16 length right before it
        if start >= 2 and struct.unpack_from("<H", data, start - 2)[0] <= len(s):
            n = struct.unpack_from("<H", data, start - 2)[0]
            s = s[:n]
        if re.search(r"\.(skn|skl|tex|dds|anm|bin|scb|sco)$", s, re.I):
            strs.append(s)
    print("ASCII asset strings:", *sorted(set(strs)), sep="\n   ")

    b = read_bin(data)
    skin_obj = next(o for o in b.objects.values() if o.class_hash == H("SkinCharacterDataProperties"))
    mesh = skin_obj.get("skinMeshProperties")
    print("\nStructured:")
    print("  skeleton   :", mesh.get("skeleton"), "->", w.has(mesh.get("skeleton")))
    print("  simpleSkin :", mesh.get("simpleSkin"), "->", w.has(mesh.get("simpleSkin")))
    tex = mesh.get("texture")
    print(f"  texture    : file {tex:016x} = {pname(tex)}  in WAD: {tex in w.entries}",
          "" if tex not in w.entries else guess_kind(w.read_entry(w.entries[tex])))
    print("  skinScale  :", mesh.get("skinScale"), " initialSubmeshToHide:", mesh.get("initialSubmeshToHide"))
    mat_link = mesh.get("material")
    print("  material   :", mat_link)
    for mo in mesh.get("materialOverride") or []:
        t = mo.get("texture"); m = mo.get("material")
        desc = f"texture {pname(t)}" if t else ""
        if m:
            mat = b.objects.get(m)
            if mat:
                samplers = mat.get("samplerValues") or []
                tx = [(s.get("textureName"), s.get("texturePath")) for s in samplers]
                desc += f"material {mat.get('name')} samplers=" + ", ".join(
                    f"{n}={pname(p) if isinstance(p, int) else p}" for n, p in tx)
            else:
                desc += f"material link {m:08x} (defined in another bin)"
        print(f"  override submesh={mo.get('submesh')!r}: {desc}")
    anim_link = skin_obj.get("skinAnimationProperties").get("animationGraphData")
    print(f"  animationGraphData link: {anim_link:08x} == fnv1a('Characters/{champ}/Animations/Skin{skin}')"
          f" -> {anim_link == H(f'Characters/{champ}/Animations/Skin{skin}')}")
    print("  dependencies containing 'Animations':", [d for d in b.dependencies if "nimation" in d])

    # ---------------------------------------------------------------- (d)
    anim_bin = next(d for d in b.dependencies if "/Animations/" in d)
    ad = w.get(anim_bin)
    ab = read_bin(ad)
    graph = ab.objects[anim_link]
    clips = graph.get("mClipDataMap")
    print(f"\n== (d) {anim_bin}: class {graph.class_hash:08x} (AnimationGraphData={H('AnimationGraphData'):08x}), {len(clips)} clips")
    kinds = collections.Counter()
    anm_rows = []
    for clip_hash, clip in clips.items():
        kinds[clip.class_hash] += 1
        if clip.class_hash == H("AtomicClipData"):
            res = clip.get("mAnimationResourceData")
            fh = res.get("mAnimationFilePath")
            anm_rows.append((clip_hash, fh))
    cls_names = {H(n): n for n in ["AtomicClipData", "SelectorClipData", "SequencerClipData", "ParallelClipData",
                                   "ConditionBoolClipData", "ConditionFloatClipData", "ParametricClipData"]}
    print("  clip classes:", {cls_names.get(k, f"{k:08x}"): v for k, v in kinds.items()})
    present = sum(1 for _, fh in anm_rows if fh in w.entries)
    print(f"  AtomicClipData -> .anm: {len(anm_rows)} (present in WAD: {present})")
    clip_guess = {H(n): n for n in ["Idle1", "Idle_Base", "Run", "Run_Base", "Attack1", "Attack2", "Crit", "Death",
                                    "Dance", "Taunt", "Joke", "Laugh", "Recall", "Channel", "Spell1", "Spell2",
                                    "Spell3", "Spell4", "Idle_In", "Run_Haste", "Respawn"]}
    for clip_hash, fh in sorted(anm_rows, key=lambda r: pname(r[1]))[:25]:
        print(f"    clip {clip_guess.get(clip_hash, f'{clip_hash:08x}'):>10}  ->  {pname(fh)}  (in WAD: {fh in w.entries})")

    # decode a few .anm headers
    print("\n  ANM header census over all clips:")
    census = collections.Counter()
    sample = None
    for _, fh in anm_rows:
        e = w.entries.get(fh)
        if not e:
            continue
        a = w.read_entry(e)
        magic, ver = struct.unpack_from("<8sI", a, 0)
        census[(magic.decode(), ver)] += 1
        if sample is None:
            sample = (fh, a)
    print("   ", dict(census))
    fh, a = sample
    magic, ver = struct.unpack_from("<8sI", a, 0)
    print(f"  sample {pname(fh)}: magic={magic} version={ver} size={len(a)}")
    if magic == b"r3d2canm":
        (res_size, token, flags, jc, fc, jcc, dur, fps) = struct.unpack_from("<IIIiiiff", a, 12)
        print(f"    resourceSize={res_size} formatToken={token:#x} flags={flags:#x} joints={jc} frames(keys)={fc}"
              f" jumpCaches={jcc} duration={dur:.4f}s fps={fps}")
    # whole-WAD anm census
    allc = collections.Counter()
    for e in w.entries.values():
        a = w.read_entry(e)
        if a and a[:4] == b"r3d2" and a[4:8] in (b"anmd", b"canm"):
            allc[(a[:8].decode(), struct.unpack_from("<I", a, 8)[0])] += 1
    print("  ANM census over the entire WAD:", dict(allc))
```

### `stream_game_hashes.py`: stream + filter CommunityDragon hashes.game.txt

```python
"""Stream CommunityDragon hashes.game.txt and keep only lines matching a substring (no full download kept)."""
import sys, time, urllib.request
needles = [n.lower() for n in sys.argv[1:]] or ["characters/ahri/"]
url = "https://raw.communitydragon.org/data/hashes/lol/hashes.game.txt"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (format-research)"})
t0 = time.time(); n = 0; kept = 0; nbytes = 0
with urllib.request.urlopen(req) as resp, open("game_hashes_filtered.txt", "w", encoding="utf-8") as out:
    for raw in resp:
        n += 1; nbytes += len(raw)
        line = raw.decode("utf-8", "replace")
        low = line.lower()
        if any(nd in low for nd in needles):
            out.write(line); kept += 1
print(f"lines={n} bytes={nbytes/1e6:.1f}MB kept={kept} in {time.time()-t0:.1f}s")
```
