# Environment look vs live League (ARAM Mayhem captures)

Owner: [env-look], 2026-10-18. Ground truth: `tools/extracted/reference/1.png` to `5.png` (YouTube, 2000x1127).
Side-by-sides (League | before | after, ours warped onto the League frame): `docs/env_look/ref{1,2,3,5}_league_before_after.jpg`.
Ref 4 is the shop panel over a dead (grey) screen, so almost no map is visible. It was not used.

## 1. What was verified exact (no change needed)

| Link in the chain | Check | Result |
|---|---|---|
| Map textures (47 diffuse, 17 lightmaps) | `assets/map/**.png` vs an independent decode of `Map12.wad` .tex (`tools/lol/tex.py`), mip 0, RGBA | **bit-exact** (max diff 0). Lightmap alpha (sun mask) kept |
| League mip chains | stored mips 1-3 vs a box filter of mip 0 | identical (Godot-generated mips are equivalent) |
| Shader math | `map_lightmap.gdshader` `league_exact` vs `defaultenv_flat.ps` blob 152 (re-read from asm) | same formula. Material links resolve to `Shaders/StaticMesh/DefaultEnv_Flat`, TintColor 0.5 |
| Godot output chain (gamma write, GammaDecodeEffect, linear tonemap, sRGB, MSAA 2x, FXAA, adjustments at 1) | `src/debug/env_chain_test.gd`: unlit patches plus real map-shader patches with known 1x1 textures | **screen == shader value**, worst error 0.6/255 |
| Map variant | Map12 also has jade/crepe/bloom/bilgewater geometry with their own MapSunProperties | the references show `base`, which is what we use |
| Dynamic lights | `base.materials.bin` has no MapPointLight or DynamicPointLight objects | none to add |
| Capture path | shop item icons in ref 4 (flat UI, 21 icons matched to `assets/ui/items`) and HUD bars | neutral. capture = 0.95·true + 9/255 (a black lift, slightly lower contrast). It does **not** add saturation |

## 2. Real causes found and fixed

1. **Texture filtering space.** Diffuse and lightmap used `source_color`, so the GPU decoded to linear, filtered
   there, and the shader re-encoded. League samples raw values and filters gamma values. Both map shaders now sample
   raw. Small effect.
2. **`fix_alpha_border` rewrote texels.** Godot's default copies neighbour RGB into alpha-0 texels. The lightmap
   alpha is the baked sun mask, and 30-60% of it is 0, so shadow edges were recoloured. It is now off for every
   map texture. `tools/lol/extract_map_geo.py` writes the import params, because `assets/` is gitignored.
   Small effect.
3. **Brush 40% too bright.** League's brush is `staticmesh/vertexdeform` with NO_BAKED_LIGHTING (blobs 30 and 38,
   decompiled): `c = diffuse * TintColor(0.636,0.641,0.723) * grassTintMap * shadow`. The grass tint map
   `assets/maps/info/map12/grasstint.tex` is about white (mean 254.6). Ours used `tint_lin*4.59*0.5`, about 0.92,
   which made the ice coral read white. Fixed in `map_blend.gdshader`.
4. The blended map pieces (ice, cloth) now use League's gamma formula `overlay(d,T)*lm*2` in place of the
   linear approximation.

## 3. Remaining difference after the exact fixes, and the calibration

Method: `src/debug/env_look_probe.gd` frames our camera on each reference (League point pinned to a pixel). It saves
the frame plus debug views of the map shader: D = overlay(diffuse,tint), baked light, sun term, and sun mask. A SIFT
homography registers our frame onto the League frame. 40-px blocks are kept only where the structure matches (no
HUD, units or VFX). Fits use 8x8 cell means, with League corrected by the icon-measured capture transfer.

Findings:
* The ratio of League to ours is the **same in sun-lit and baked-shadow cells** (1.07/1.15/1.21 vs
  1.04/1.12/1.21). So the cause is not the sun term or its mask.
* After capture correction, luminance matches in the lanes. The difference is a **cool white-balance shift**: warm
  cells get cooler too (R x0.89, B x1.04). A saturation or contrast grade would make them warmer, so the shift is not
  a grade.
* The best model of the form `League = g ⊙ (D·L)`, fitted on refs 1, 2 and 5, gives a pure per-channel
  **gain (0.911, 1.049, 1.151)**. Its luminance factor is 1.02. The best saturation term is 1.00.
* The decompiled shader cannot produce this. LIGHT_MAP_COLOR_SCALE is a scalar, and there is no ambient term or
  grade. The source is unknown: a CPU constant, a lightmap re-bake between the video's patch and this install, or the
  stream.

The calibration is applied as `CALIB_GAIN` in `map_lightmap.gdshader` and `map_blend.gdshader`. It covers map
surfaces only, which is where it was measured. It does not apply to the HUD, characters or VFX. The code comments
say it is a fit to captured frames. `calibrate = false` (or `--el_nocal=1` in the probe) gives the pure League
formula. Because `g·(D·L) = (g·D)·L`, applying the gain to the albedo is exact.

## 4. Measured stats (matched map pixels; dead ref 3 has League's death desaturation applied to ours)

| Ref | | Y p10 / med / p90 | S med | mean RGB | RMS vs League* |
|---|---|---|---|---|---|
| 1 | League raw / *corrected | 41.9 / 71.9 / 123.5 · 33.7 / 65.0 / 119.1 | 0.572 · 0.627 | 61 81 114 · 54 75 108 | |
| 1 | before → after | 36.0 / 77.6 / 112.6 → 36.9 / 79.9 / 114.9 | 0.488 → 0.587 | 64 78 101 → 59 81 114 | 22.7 → 21.3 |
| 2 | League raw / *corrected | 73.1 / 109.8 / 167.8 · 66.5 / 104.8 / 165.3 | 0.594 · 0.631 | 75 124 186 · 68 119 185 | |
| 2 | before → after | 64.9 / 94.1 / 136.9 → 66.9 / 97.3 / 142.1 | 0.542 → 0.636 | 68 103 150 → 62 108 171 | 30.0 → 21.3 |
| 5 | League raw / *corrected | 52.3 / 96.6 / 153.4 · 44.6 / 91.0 / 150.4 | 0.549 · 0.590 | 70 104 149 · 62 99 146 | |
| 5 | before → after | 54.4 / 89.5 / 131.8 → 56.1 / 91.7 / 132.4 | 0.490 → 0.595 | 69 95 131 → 62 98 147 | 27.8 → 22.3 |
| 3 (dead) | League raw | 64.2 / 98.8 / 139.9 | 0.338 | 86 103 125 | |
| 3 (dead) | before → after (death F=1) | 66.2 / 90.3 / 120.7 → 68.4 / 94.1 / 124.2 | 0.135 → 0.174 | | 24.0 → 21.5 |

The residual RMS of about 21 is mostly registration error, compression and unmasked effects. Saturation now matches
within 0.04 on every live frame.

## 5. Open items (not fixed here)

* **Death screen ([hud-ref], `death_gray.gdshader`).** In ref 3 ("BACK IN 17", fully dead) League keeps about
  60% of the live saturation (S 0.34-0.37 vs about 0.60). With `g = mix(c, 0.8·lum+0.2·c, F)` that means
  F ≈ 0.5, not 1. Ours at F=1 gives S 0.17.
* **Base highlights (ref 2).** League's p90 is about 165 against our 142 after the fix. The large bright blue
  fountain/platform glow by the hexgate (top of ref 2) is missing from ours. No fountain system is in
  `map12_particles.json`, so it probably comes from the shrine turret's or fountain's own particle ([vfx]/structures).
* **Characters.** The calibration does not touch them. League minions in refs 1 and 5 look brighter and more cyan
  than ours. lit_uber caps them at the texture colour, and ours give L about 0.76-0.97 on side normals. This points
  to LIGHTGRID_SCALE or the grid byte order (docs/LEAGUE_SHADERS.md section 8). It needs a clean champion-vs-champion
  capture. MapLightingV2.MinimumEnvironmentColorContribution = 0.8 is a candidate floor for L.
* **Snow.** League's `HA_Env_Snow_01` flakes texture is BC1 with an RGB maximum of 41/255 (additive, 270/s). Our
  camera snow stands in ([vfx], `map_ambient.gd` `_strip_snow_quads`).
* **Turret size.** The model scale is right: skinScale 750/770 is applied, and the placement transforms have no
  scale. No change.
