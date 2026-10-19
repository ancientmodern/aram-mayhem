# League shaders: exact math from the shipped shader cache

Author: [shader-re]. Source: offline disassembly of `DATA/FINAL/ShaderCache.dx11.wad.client` (data file only;
the game process was never touched). Tool: `tools/lol/extract_shaders.py`. Output:
`tools/extracted/shaders/<path>.<ps|vs>/b<blob>.asm` + `index.txt` per shader, `INDEX.txt` / `index.json` overall.

Confidence tags: **[exact]** = read straight from the bytecode. **[cpu?]** = the shader is exact, but the value
fed in by the CPU is inferred. **[guess]** = a hypothesis that needs a screenshot check.

---------------------------------------------------------------------------------------------------------------

## 0. Container format and coverage

* TOC `<path>.ps-dx11`: `str "TOC3.0"`, `u32 nperm, ndef, nblob, stage(0 vs / 1 ps)`, `str "baseDefines"`,
  `ndef x (str name, str value)`, `str "shaders"`, `nperm x u64 hash`, `nperm x u32 blobIndex`.
  `hash = xxh64("".join(f"{k}={v}" for k, v in sorted(enabledDefines)))`. All defines are optional toggles. A name that
  appears twice (`USE_RIM=0`, `USE_RIM=1`) is a mutually exclusive choice.
* Blob bundle `<path>.ps-dx11_<N>` (N = blob // 100 * 100) holds blobs N..N+99. Each entry is `u32 n`, then
  `n-1` bytes of DXBC, then 1 trailing byte (0x35).
* 853 shader TOCs (all named), 74,098 unique compiled blobs (~1.5 GB of DXBC). Permutation defines were recovered for
  all but 12 exotic TFT/skin shaders. 7,946 blobs are disassembled with RDEF reflection (constant names, cbuffer
  layouts, bindings): every blob of the shaders that matter here, plus 2 per other shader. Run `--all --filter X`
  for more.
* `DATA/FINAL/Shaders/Shaders.wad.client`: `data/shaders/shaders.bin` holds 350 `CustomShaderDef` entries
  (material params and defaults), and `assets/shaders/shareddata.bin` holds `X3DSharedData` (shared cbuffers,
  samplers and textures). Particle blend states are **not** in shader data; the CPU picks them from `blendMode`.
  Map materials (`StaticMaterialPassDef`) carry `blendEnable` and src/dst factors (6 = SrcAlpha, 7 = InvSrcAlpha).

## 1. Colour space (answers "do League shaders do any sRGB conversion?")

Every shader ends with the same epilogue **[exact]**:

```hlsl
if (RENDERTARGET_IS_SRGB != 0 && DEBUG_RENDERTARGET_IS_SRGB_HANDLED != 1234)
    out.rgb = pow(out.rgb, 2.2);          // gamma -> linear, only so an sRGB RT re-encodes it
```

The post shader (`gamma/ps_gamma`) does the mirror step: `if (BACK_BUFFER_COPY_IS_SRGB) c = pow(c, 1/2.2)`.
The newer PBR permutations (lit_uber `FEATURE_ROUGHNESS_METALLIC`, `FORCE_MANTIS_LIGHTING`) linearize albedo with
`pow(albedo, 2.2)` unless `ALBEDO_IS_SRGB`, light in linear, tonemap, then **explicitly** return to gamma with
`pow(x, 1/2.2)` before the epilogue.

Conclusion:
* All legacy shading (particles, lit_uber, DefaultEnv_Flat) is written in **gamma space on raw texture values**.
  Textures are sampled without sRGB decode. **[exact]**
* The frame buffer's working values are gamma values. Even the linear PBR path converts back to gamma before
  writing, and post-processing (bloom, death grey, gamma LUT) runs on gamma values. **[exact]**
* The sRGB-RT flags are a compatibility path (a 2.2 power, not the sRGB curve). On the normal UNORM back buffer,
  blending (alpha and additive) therefore happens on gamma values. **The gamma-space blending switch is
  confirmed.** **[exact shader math; high confidence that the default RT is non-sRGB]**
* Where League converts, it uses `pow 2.2` / `pow 1/2.2`, not the piecewise sRGB curve (minor).

## 2. Particles (`hlsl/particlesystem/quad_vs` + `quad_ps`, `mesh_vs` + `mesh_ps`)

Defines (quad_ps): `DISABLE_FOW MASKED COLORPALETTE_COLORBLIND SOFT_PARTICLES PALETTIZE_TEXTURES ALPHA_EROSION
ALPHA_TEST MULT_PASS` (all 256 combinations compiled). mesh_ps adds `SEPARATE_ALPHA_UV REFLECTIVE SCREEN_SPACE_UV`.
The CPU builds the per-vertex data (uv transforms, colour over life, birth colour), so the shader sees final values.

### 2.1 quad_vs [exact]
```hlsl
// inputs: POSITION(world), COLOR(BGRA8 -> .zyxw swizzle), TEXCOORD0 = (u, v, frame, erosionThreshold), TEXCOORD1 = colorTexUV
float3 p   = pos + normalize(pos - vCamera) * PARTICLE_DEPTH_PUSH_PULL;   // depth push/pull along the view ray (world units)
o.pos      = mul(mProj, float4(p,1));
o.color    = COLOR.bgra;                     // UNORM8: per-vertex colour is clamped to [0,1] and 8-bit
float row  = floor(floor(frame) * TEXTURE_INFO.y);                  // TEXTURE_INFO = (cols, 1/cols, 1/rows, -)
float col  = floor(frame) - row * TEXTURE_INFO.x;
o.uv0      = (float2(col,row) + uv) * TEXTURE_INFO.yz;              // flipbook cell
o.uv1      = TEXCOORD1;                                             // PARTICLE_COLOR_TEXTURE uv (or the MULT uv)
o.fowUV    = worldPos.xz * FOG_OF_WAR_PARAMS.xy + FOG_OF_WAR_PARAMS.zw;
o.erosionT = TEXCOORD0.w;                                           // ALPHA_EROSION only
// MULT_PASS: the mult texture is flipbooked with the same frame using TEXTURE_INFO_2 and uv from TEXCOORD1
```
Because the vertex format is BGRA8, a particle colour above 1.0 cannot exist in League. **[exact swizzle; format inferred]**

### 2.2 quad_ps, all features [exact]
```hlsl
float4 c = TEXTURE.Sample(uv0);
if (PALETTIZE_TEXTURES) {                     // palette replaces rgb; texture alpha kept
    float u = saturate(dot(c, cPaletteSrcMixerMain)) + cPaletteSelectMain.z;
    float v = cPaletteSelectMain.w + cPaletteSelectMain.x;
    c.rgb  = sPalettesTexture.Sample(float2(u, v)).rgb;               // palette alpha is NOT used
}
if (MULT_PASS) c *= TEXTUREMULT.Sample(uv1);                          // rgba
c *= PARTICLE_COLOR_TEXTURE.Sample(uv1);                              // rgba (white 1x1 when unused)  [not in the ALPHA_EROSION variant]
if (ALPHA_TEST) clip(color.a * c.a - AlphaTestReferenceValue);        // tested with vertex alpha included
c *= color;                                                           // vertex colour, rgba
c.rgb = PIXEL_COLOR_REMAP_RAMP(lum709(c.rgb)) if ramp.a > 0           // colour-blind remap, no-op normally
if (!DISABLE_FOW) c.rgb *= FOW_MAP.Sample(fowUV).a;                   // fog of war darkens rgb only
if (ALPHA_EROSION) {
    float e = saturate(dot(sAlphaErosionTexture.Sample(uv0), cAlphaErosionTextureMixer));
    float t = erosionT;                                               // per-particle (TEXCOORD0.w)
    c.a *= saturate((t - e + cAlphaErosionParams.y) * cAlphaErosionParams.z)
         - saturate((t - e)                         * cAlphaErosionParams.w);
}
if (SOFT_PARTICLES) {
    float dz = linZ(sDepthTexture[pix]) - linZ(fragDepth);            // linZ(d) = 1/(d*cDCP.y + cDCP.x)
    float2 k = saturate((dz - cSoftParticleParams.xy) * cSoftParticleParams.zw);
    float  f = smoothstep01(k.x) - smoothstep01(k.y);                 // fade-in near the surface, optional fade-out far
    c.rgb = c.rgb * (cSoftParticleControl.x + f * cSoftParticleControl.y);
    c.a   = c.a   * (cSoftParticleControl.z + f * cSoftParticleControl.w);
}
if (MASKED) c.a = min(c.a, NAVMESH_MASK_TEXTURE.Sample(maskUV).r);
out = c;   (+ sRGB epilogue)
```
* `cSoftParticleParams` is most likely `(beginIn, beginOut, 1/deltaIn, 1/deltaOut)`. `cSoftParticleControl` chooses
  whether the fade hits rgb (premultiplied/additive) or alpha (alpha blend). **[cpu?]**
* Erosion is a band: `[t, t + P.y]` with feather `1/P.z` and `1/P.w`. With `P.w = 0` it is a plain threshold, and
  visible texels are those with `e < t + P.y`. The CPU must therefore feed `t` rising from 0 to 1 to *reveal*, so
  `t = 1 - erosionDrive` or similar. **[cpu?]**

### 2.3 mesh_vs / mesh_ps (VfxPrimitiveMesh) [exact]
```hlsl
// VS: per-instance World0..2, uv 3x2 transform (vParticleUVTransform), colour kColorFactor, PARTICLE_DEPTH_PUSH_PULL as quads
float ndv  = saturate(dot(-normalize(worldPos - vCamera), worldNormal));   // one-sided, not abs()
o.fresnel  = (1 - pow(ndv, vFresnel.w)) * vFresnel.rgb;
o.fowUV    = worldPos.xz * FOG_OF_WAR_PARAMS.xy + .zw;  o.fowH = saturate(worldPos.y * FOG_OF_WAR_ALWAYS_BELOW_Y.z + .w);
// PS
float4 c = TEXTURE.Sample(uv) * PARTICLE_COLOR_TEXTURE.Sample(perVertexLookup ? uvLookup : COLOR_LOOKUP_UV) * color;
if (SEPARATE_ALPHA_UV) c.a = TEXTURE.Sample(alphaUV).a * ...;          // rgb and alpha at separate uvs (uvMode LockAlpha)
if (SCREEN_SPACE_UV)   uv = uvw.xy / uvw.z;
if (REFLECTIVE) c.rgb += REFLECTION_MAP(cube).rgb * f * lerp(1, vReflectionFColor.rgb, f);  // f = per-vertex reflection fresnel
c.rgb += o.fresnel * c.a;                                               // fresnel ADDS colour, scaled by alpha; alpha untouched
c.rgb  = saturate(c.rgb * lerp(FOW_EDGE_CONTROL.w, FOW_MAP.a, fowH));   // note the saturate on meshes
```
`vFresnel = (fresnelColor.rgb, fresnel)` **[cpu?]**.

### 2.4 distortion_vs / distortion_ps [exact]
```hlsl
float2 n   = NORMAL_MAP.Sample(uv0).xy;  float na = NORMAL_MAP.Sample(uv0).a;
float4 ct  = PARTICLE_COLOR_TEXTURE.Sample(uv1);
float2 suv = screenUV + (n - 0.5) * 2 * DistortionPower * ct.a;      // offset in screen-uv units
float3 bg  = SAMPLER_BACK_BUFFER_COPY.Sample(suv).rgb;
out.rgb = bg * TEXTURE.Sample(uv0).rgb * color.rgb * ct.rgb;           // the texture TINTS the refracted image
out.a   = na * ct.a;                                                   // alpha = normal-map alpha (x colour-texture alpha)
```

### 2.5 Generated particle materials (`Shaders/Particles/*`, used via StaticMaterialDef)
`DefaultParticleQuadUnlit` [exact]: `col = lerp(dot(D, Color_ChannelToUse), D.rgb, Color_Use_TextureColor) * color.rgb`
(times `color.rgb` again if `switch_PARTICLE_COLOR_ACTIVE`). `alpha = saturate(dot(lerp(D, Alpha_Texture,
Alpha_Texture_USE), Alpha_ChannelToUse)) * color.a` (times `color.a` again if the switch is set), then `min(alpha,
navmask)` when `switch_NAVMESH_MASK_ACTIVE`. `VFX_Uber_StaticMesh_Unlit` (24 blobs) exposes
`MULT_ACTIVE / EROSION_ACTIVE / UV_DIST_ACTIVE / COLOR_GRADIENT_ACTIVE / *_POLAR_UV` choices. Asm is extracted; it is not
decoded here because ARAM base content rarely uses it.

## 3. Skinned meshes (champions, minions, structures): `hlsl/skinnedmesh/lit_uber_vs` + `lit_uber_ps`

Defines: `DISABLE_SHADOWS SEPARATE_ALPHA_UV TRANSITION USE_MAP_RIM_LIGHT FEATURE_ROUGHNESS_METALLIC DISABLE_FOW
FORCE_MANTIS_LIGHTING FEATURE_TANGENT REFLECTIVE LOW_QUALITY_MODE USE_DYNAMIC_LIGHTING`. The base blob is identical
for `(none)`, `DISABLE_SHADOWS`, `LOW_QUALITY_MODE` and `USE_MAP_RIM_LIGHT`: there is **no rim light and no shadow
receive** in the legacy path.

```hlsl
// VS [exact]
skin with up to 4 BONES (float4x3), world normal N
o.fowUV   = world.xz * FOG_OF_WAR_PARAMS.xy + .zw
o.fresnel = 1 - pow(saturate(dot(-V, N)), vFresnel.w)       // computed, unused by the legacy PS
o.ambient = N.x*N.x * LIGHTGRID_COLORS[N.x<0 ? 1:0]        // Valve-style ambient cube, per vertex
          + N.y*N.y * LIGHTGRID_COLORS[N.y<0 ? 3:2]        // [0]=+X [1]=-X [2]=+Y(up) [3]=-Y [4]=+Z [5]=-Z
          + N.z*N.z * LIGHTGRID_COLORS[N.z<0 ? 5:4];
// PS [exact]
float4 d  = DIFFUSE_MAP.Sample(uv);   clip(d.a == 0 ? -1 : 1);               // only fully transparent texels are discarded
float  em = EMISSIVE_MAP.Sample(uv).g;                                        // green channel; black when absent
float3 L  = saturate(LIGHTGRID_SCALE.y * SELF_ILLUMINATION
                     + saturate(1 - em) * ambient * LIGHTGRID_SCALE.x + em);
float3 c  = saturate(d.rgb * L);
if (USE_DYNAMIC_LIGHTING)                                                   // clustered point/spot lights
    c = saturate(d.rgb * L + Σ d.rgb * lightColor * max(dot(Ldir, N), 0) * (1 - saturate(dist * invRadius)));
c = colourblindRemap(c);
float4 fow = FOW_MAP.Sample(fowUV);
c = lerp(fow.rgb, c, fow.a);                                                 // fog tints toward the FOW colour
out = float4(c, d.a * kGrassFade.w);   out1 = (0,0,0,1);                     // kGrassFade.w = brush/stealth fade
```
* **No sun N·L, no specular, no rim/fresnel** in the default champion shader. Directional shading comes only from the
  6-colour ambient cube that the CPU samples from the map light grid at the unit position. **[exact]**
* `SELF_ILLUMINATION` brightens by raising the multiplier toward 1 (`d * saturate(L + s)`), never past the
  texture colour. This is the only per-draw "flash" lever; League cannot flash white through this shader. **[exact]**
* Point lights are lambert with **linear** falloff `1 - d/r`, added on top and clamped. **[exact]**
* Characters are not shadowed by the sun in the legacy path (only spot-light shadows under USE_DYNAMIC_LIGHTING). **[exact]**
* `FORCE_MANTIS_LIGHTING` / `FEATURE_ROUGHNESS_METALLIC` are the new SR (light regions, IBL cube array, cloud cards)
  PBR paths with an ACES-style fit `x=0.6c; (x(1.506x... )`. Howling Abyss uses legacy materials (`DefaultEnv_Flat`)
  and has `LightGrid.dat`, so ARAM characters almost certainly use the legacy path above. **[guess, medium-high]**

### 3.1 Light grid data (feeds LIGHTGRID_COLORS)
`Map12.wad: assets/maps/lightmaps/maps/mapgeometry/map12/base/lightgrid.dat` (1,572,896 bytes) **[exact layout]**:
header `u32 version=3, u32 headerSize=32, u32 w=256, u32 h=256, f32 12877.53, f32 12877.53 (world extent),
f32 0.8501, f32 0.5`, then `256*256 cells x 6 faces x 4 bytes`. [look2, verified from data, docs/ENV_LOOK.md
section 6] Face order +X,-X,+Y,-Y,+Z,-Z (League axes); byte order BGRA (alpha always 255); rows = League z, columns
= League x, cell (0,0) at `MapContainer.boundsMin` (-28.43, -19.03), whose extent to boundsMax is the header 12877.5. Typical values: +Y ≈ 0.18-0.20, sides ≈ 0.08-0.14.
`MapBakeProperties.lightGridCharacterFullBrightIntensity = 0.5` (the last header float) suggests the grid is stored at
half intensity, i.e. `LIGHTGRID_SCALE.x ≈ 1/0.5 = 2`. **[cpu? / guess]** The map also has
`MapSunProperties.lightMapColorScale = 2.0`, sun colour (0.365,0.384,0.392), dir (-0.38,0.707,0.05), fog
colours, and `MapLightingV2.MinimumEnvironmentColorContribution = 0.8`.

## 4. Environment: `Shaders/StaticMesh/DefaultEnv_Flat` (+ `_AlphaTest`), what all of Map12 uses

Map12 `base.materials.bin`: 39 DefaultEnv_Flat, 10 DefaultEnv_Flat_AlphaTest (some alpha-blended with SrcAlpha /
InvSrcAlpha), 1 VertexDeform (the brush). Base permutation (b0152) **[exact]**:
```hlsl
// VS: world pos W, world normal N, uv0, lightmap uv (TEXCOORD7)
shadowPos = mul(mShadowProj, W + N * (1 - |dot(N, SUN_DIR)|) * NORMAL_OFFSET_BIAS)    // normal-offset shadows
fowH      = saturate(W.y * FOW_HEIGHT_FADE.x + FOW_HEIGHT_FADE.y)
// PS
float3 Nf   = normalize(cross(ddx(W), ddy(W)));                         // face normal for bias only
float  bias = CONSTANT_DEPTH_BIAS + SLOPE_SCALED_DEPTH_BIAS * (1 - saturate(dot(Nf, SUN_DIR)));
float  sh   = 0.2 * Σ5 PCF(shadowPos.xy + {0, ±SHADOW_SAMPLE_OFFSETS.xy, ±.zw}, shadowPos.z - bias);
float4 bl   = BAKED_LIGHT.Sample(lmuv * BAKED_LIGHT_SCALE_AND_BIAS.xy + .zw);
sh          = min(sh, bl.a);                                            // baked sun-shadow mask in lightmap ALPHA
float3 light = bl.rgb * LIGHT_MAP_COLOR_SCALE_AND_INTENSITY             // = 2.0 on Map12
             + SUN_LIGHT_COLOR.rgb * max(dot(N, SUN_DIR), 0) * sh;      // live sun term on top of the bake
float4 d    = DiffuseTexture.Sample(uv);
float3 base = overlay(d.rgb, TintColor.rgb);                            // d<.5 ? 2dT : 1-2(1-d)(1-T); T=0.5 -> identity
float3 c    = base * light;                                             // no saturate, no ambient, no specular
float  t    = saturate((W.y - FOG_END) / (FOG_START - FOG_END));        // ENV_FOG_START_END...xy, height fog
float  fog  = max((exp(-2*smoothstep01(t)) - exp(-2)) / (1 - exp(-2)), 0);
c = lerp(c, lerp(ENV_FOG_COLOR, ENV_FOG_ALT_COLOR, fog), fog);          // Map12 fog is far below the playfield (no effect)
float4 fow = FOW_MAP.Sample(fowUV);  float k = fow.a + fowH * (1 - fow.a);
c = lerp(fow.rgb, c, k);
out = float4(c, d.a);
```
Alpha test variants discard below `AlphaTestValue`. `MULTIPLY_ALPHA` / `PREMULTIPLIED_ALPHA` are material switches.

## 5. Fog of war [exact]
`fogofwar/applyoverlayandcolor` builds FOW_MAP from the blurred visibility `v` and an overlay texture:
```hlsl
float4 ov = fowOverlay.Sample(uv * FOG_OVERLAY_UV_ANIMATE.xy + .zw);    // Map12 base overlay: rgb (0.051,0.125,0.216), a ≈ 0.35-0.40
float  e  = saturate(v * FOW_EDGE_CONTROL.z);
FOW.rgb = lerp(ov.rgb, float3(0.20, 0.07, 0.06), e);   FOW.a = lerp(ov.a, 1, v);
```
Consumers: env and characters `c = lerp(FOW.rgb, c, FOW.a)` (fully fogged: 60% dark blue + 40% scene). Quad
particles `rgb *= FOW.a`. Mesh particles `rgb *= lerp(FOW_EDGE_CONTROL.w, FOW.a, heightFade)`. `fade.ps` steps the
visibility toward the target by `PARAMETERS.x` / `.y` per frame (asymmetric reveal/hide speeds).

## 6. Post chain [exact]
* `gamma/ps_gamma` (the final pass): `c = backbuffer` (gamma). With BLOOM: `c = 1 - (1-c)(1-bloom)` (screen). With
  BLOOM+ADDITIVE: `c += bloom * BLOOM_INTENSITY_SCALE`. Then a per-channel 1D LUT `SAMPLER_GAMMA_LOOK_UP` (the
  ColorGamma setting; game.cfg ColorGamma=0.5, presumably identity). With DEATH_EFFECT: `g = lerp(c, 0.8*lum601(c) +
  0.2*c, F)`, `t = lerp(c, TINT.rgb, TINT.a)`, `out = lerp(t, g, F)`, where `F = DEATH_EFFECT_APPLY_FRACTION`.
* Bloom: 13-tap mip-chain downsample (weights 0.5 / 0.125 / 0.25 x 0.25) and a 3x3 tent upsample (1-2-1 / 16), plus a
  7-tap gauss `bloom.ps` (0.383, 0.242, 0.061, 0.006). The source is the second render target, which every shader
  above writes as `(0,0,0,1)`: only bloom-flagged materials feed bloom. **No tonemap and no colour grade in the
  legacy pipeline.**
* AA: `fxaa_ps` and `smaa/*` exist (user option). `ssao/ssaosimple` and `gamma/dof` exist but are off in normal play.
* Hover outline: `filters/ps_dilate_green` + `ps_blur_green` + `ps_mouseover_outline_blend` (a mask in green,
  dilated and blurred, drawn with a vertex colour). **There is no depth-Sobel "inking" pass in the cache**: no shader
  samples depth for edges other than soft particles and decals.

---------------------------------------------------------------------------------------------------------------

## 7. Discrepancy list (our runtime vs League)

| # | Area / file | League (from bytecode) | Ours | Suggested fix | Conf. |
|---|---|---|---|---|---|
| 1 | gamma pipeline (`gamma_decode_effect.gd`, `gamma.gdshaderinc`) | All math and blending on gamma values; conversions use pow 2.2 | Same idea, piecewise sRGB enc/dec | **Keep.** Optional: `gamma_enc` -> `pow(x,1/2.2)` and the decode -> `pow(x,2.2)` for bit-parity | high |
| 2 | particle fresnel (`lol_particle` + `lol_vfx.gd:1806`) | `F = 1 - pow(saturate(N·V), fresnel)`; `rgb += fresnelColor * F * alpha`; alpha unchanged | `rim = pow(1-ndv, 0.5/f clamped)`; `abs(N·V)`; also raises alpha (`max(c.a, rim...)`) | `float F = 1.0 - pow(clamp(dot(N,V),0,1), fresnel_f); c.rgb += fresnel_color.rgb * F * c.a;` and pass raw `fresnel` (no remap); drop the alpha change (keep `rim_alpha` only if a specific asset needs it) | high (shader) / med (`w = fresnel`) |
| 3 | particle palette | `u = saturate(dot(tex, mixer)) + select.z`, `v = select.w + select.x`; rgb replaced; **alpha = tex.a only** | `tx.r` only; `alpha *= palette.a` | Use the channel mixer and offset; don't multiply palette alpha | high |
| 4 | particle alpha test | `clip(vertexA * texA * colorTexA - ref)` | PREMUL path tests texture alpha only | Include `v_color.a` in the test value | high |
| 5 | particle erosion | Band `sat((t-e+w)*a) - sat((t-e)*b)`, visible where e < t (+w) | `clamp((e-th)/feather+.5)` | Port the exact form with `w = sliceWidth`, `a = 1/featherIn`, `b = 1/featherOut (0 = off)`, `t = 1 - drive` | med (CPU mapping) |
| 6 | soft particles | `smoothstep(k.x) - smoothstep(k.y)`; applied to rgb (additive) or alpha (blend) | `smoothstep(begin, begin+dist)` on alpha (+rgb in PREMUL) | Add the optional far fade (`beginOut / deltaOut`); otherwise equivalent | high |
| 7 | particle colour range | Vertex colour is BGRA8: clamped to [0,1] before the shader | `intensity` uniform and HDR colours can exceed 1 | Clamp particle colour (rgb, a) to [0,1] where it is built; avoid `intensity > 1` | med-high |
| 8 | distortion (`DISTORT`) | `suv = screenUV + (2n-1) * DistortionPower * ct.a`; `rgb = bg * tex.rgb * color.rgb`; `a = normal.a * ct.a` | `n * strength * 0.15 * mask`, border fade, `ALPHA = m*0.7`, no tint | Use the exact offset (strength = League `distortion` value, no 0.15) and tint by `tex.rgb * color.rgb`; mask by normal-map alpha. The quad-patch problem is the missing transparent pass in Godot's screen copy, not League math | high |
| 9 | particle FOW | quads `rgb *= FOW.a`; meshes `rgb = saturate(rgb * lerp(edge.w, FOW.a, h))` | none | Add once a FOW texture exists | high |
| 10 | mesh particles saturate | Mesh output rgb is saturated | not clamped | `c.rgb = clamp(c.rgb, 0, 1)` for mesh primitives | high |
| 11 | champion lighting (`champion.gdshader`) | `c = sat(d * sat(ambientCube(N)*S.x*(1-em) + em + S.y*selfIllum))` + linear-falloff point lights; no sun, no rim, no hemi, no wrap | 60% unlit + wrapped lambert from the directional light + hemi + rim 0.10 | Replace with the ambient cube: load `lightgrid.dat` (BGRA, 6 faces), sample the cell at the unit position (CPU, per unit), and pass 6 colours as instance uniforms. Ambient per vertex as in the VS. `S.x ≈ 2` [guess], `S.y*selfIllum = 0` normally. Remove the rim, the directional light() term and the hemi term. Point lights: `d*col*max(N·L,0)*(1-d/r)` | high (shader) / med (S.x) |
| 12 | champion emissive | `EMISSIVE_MAP.g` lifts L toward 1 (`L = (1-em)*amb + em`) | none | Support when a skin has an emissive map | high |
| 13 | champion hit flash / glow | Only lever is SELF_ILLUMINATION: `d*sat(L+s)`, which caps at the texture colour | `flash` adds white 0.8, `glow` adds colour | Match: flash = raise L to 1 (full-bright texture), not additive white | high |
| 14 | champion alpha | Discards only `a == 0`; `alpha = d.a * kGrassFade.w` | scissor 0.35 option; dither `fade` | Alpha clip at `a == 0` (or tiny); brush/stealth = alpha multiply (`kGrassFade.w`), not dither | high |
| 15 | champion ink (`champion_ink.gdshader`) | **No** ink/outline pass for characters exists in the shader cache (only the hover outline). Silhouette darkness is painted in the textures | inverted-hull dark line | Disable the ink pass by default (or keep as a hover-outline basis: green-mask dilate/blur) | high |
| 16 | champion FOW | `c = lerp(FOW.rgb, c, FOW.a)` | none | With the FOW texture: `mix(fow.rgb, c, fow.a)` (overlay rgb (0.051,0.125,0.216), a 0.4) | high |
| 17 | map lighting (`map_lightmap.gdshader`) | `overlay(d, Tint) * (lm.rgb*2 + sunColor*max(N·L,0)*min(pcf5, lm.a))` in gamma; no saturation, no grade | `d*lm*4.59*tint*4.59*brightness`, saturation 0.97, gain 1.2, contrast 1.14, tint (1.03,1,.93); shadow = `mix(shadow_color,1,att)` multiplied | In gamma mode sample diffuse/lightmap raw (no `source_color`), compute exactly League's line, output as-is. Overlay with tint 0.5 = identity (drop the ×4.59 tint factor). The lightmap **alpha** is the baked sun-shadow mask (check the PNG export keeps it). The live sun term uses Map12 sun (0.365,0.384,0.392), dir (-0.38,0.707,0.05) (League axes; flip z for ours). Shadow = 5-tap PCF min'd with lm.a, scaling only the sun term (never darkening the baked part). Then delete the grade constants. (4.59 = 2^2.2 was the correct linear equivalent of lightMapColorScale 2.0) | high |
| 18 | map alpha | `out.a = d.a`; AlphaTest discards < AlphaTestValue; blended mats SrcAlpha/InvSrcAlpha | similar | OK | high |
| 19 | post | Final = gamma LUT (identity at default), optional screen-blend bloom from bloom-flagged materials only, death = desat 0.8*lum601 + tint | Godot tonemap / glow | Tonemap linear/off; glow off except a bloom-flagged buffer; death screen per formula | high |
| 20 | colour-blind remap | `PIXEL_COLOR_REMAP_RAMP` on Rec.709 luma, active when ramp.a > 0 | none | Ignore (off by default) | high |

## 8. Open items (need a reference screenshot, not more RE)
* `LIGHTGRID_SCALE.x` (2.0?) and the light-grid byte order: compare a champion's lit/unlit sides at mid-lane with a
  League capture.
* Particle blend factors per `blendMode` are CPU-side. The shader outputs straight `rgb, a` with no premultiply, so
  "additive" = ONE,ONE on (premultiplied by CPU vertex colour) or SRC_ALPHA,ONE. Our PREMUL_ADD path matches the
  first.
* `vFresnel.w` == emitter `fresnel` and the erosion parameter packing are the most likely CPU mappings, but are
  unverified.
