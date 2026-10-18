# VFX coverage: how faithfully our runtime emulates League's particle system

Owner: [vfx-runtime]. Regenerate the tables with `python tools/lol/vfx_coverage.py` (add `--rescan` after game
patches). It reads the RAW `VfxSystemDefinitionData` of every system in `data/vfx/*.json` from the game bins (not our
json), weights each field by how often the system spawns in play (VFXLOG counts from `--sim --vfxlog` logs in
`tools/extracted/vfxcov/*.log`), and checks three things per field: extracted by `tools/lol/extract_vfx.py`, read by
the runtime (`src/vfx/lol_vfx.gd`, `lol_process.gdshader`, `lol_particle.gdshader.txt`, `lol_trail.gd`), and whether
its semantics are confirmed by external evidence.

## Evidence sources (ground truth)

- **[wiki]** LeagueToolkit meta-wiki (`github.com/LeagueToolkit/lol-meta-wiki`, `db/docs/VfxEmitterDefinitionData.yaml`
  and the `VfxPrimitive*` / `VfxTrailDefinitionData` pages): reverse-engineered field semantics from the client.
- **[rey]** ReyEngine (`github.com/TheKillerey/ReyEngine`, MIT): a C# League VFX renderer with research notes
  (`docs/research/vfx-blend-modes.md`, `q4-miscrenderflags.md`, `ParticleQuadBuilder.cs`, `VfxUvTransform.cs`).
- **[bc]** `docs/LEAGUE_SHADERS.md`: League's shipped DX11 particle shaders, disassembled (exact math).
- **[corpus]** statistics over our own raw bins, e.g. the arbitrary-quad texture aspect census and the
  "flat ground glow" Euler-order census below.

## Reference renderer feasibility

- **modelviewer.lol** does not play particle systems (models, animations and material UV effects only; no `.bin`
  or VFX data is fetched). Not usable as an automatic reference.
- **ReyEngine** renders League particle systems (D3D11 + GL, Windows/.NET) and has an offscreen single-system
  render harness (`AatroxTrace blend <champ> <outDir> <skin> <system> [age]`). It is the only feasible automatic
  side-by-side reference; building it needs the .NET 10 SDK, not set up here. ltk-manager (GPL-3, Tauri/Three.js)
  also previews systems, but only interactively.

## Fixes in this round (evidence -> change)

| # | field(s) | was | now | evidence |
|---|---|---|---|---|
| 1 | `disabled`, `Filtering.keywordsRequired` / `spectatorPolicy` | rendered (433 disabled + 34 skin-only emitters; 7 systems are fully disabled) | dropped at extraction | [wiki] spawn gates |
| 2 | `0x4ffce322` (= `FlexShapeDefinition`) | misread as "softParticle", 1192 emitters soft-faded | ignored (bound-object scale ~1) | CommunityDragon hash list, [wiki] |
| 3 | `VfxPrimitiveArbitraryQuad` uv | camera-quad mapping (texture turned 90 deg + mirrored on 1525 aquads) | `u = y + 0.5, v = 0.5 - x` | [wiki][rey]; [corpus] aquads authored with swapped aspect 52 vs 9, billboards 33 vs 7 |
| 4 | euler order of `birthRotation0` | X, Z, Y (ROT_ORDER 4) | Z, X, Y | [wiki][rey]; [corpus] 71 flat-named ground glows lie flat only under Z-X-Y, 0 only under the old order |
| 5 | missile frame | League Z = down | League X right, Y = travel, Z = up | Ezreal Q `ground_glow` at z = -100, `Leading_glow` +Y, trailing `Mesh_cone` -Y; Yasuo wind-wall meshes stand up |
| 6 | camera-quad `birthScale0` | forced square (x) | half-width x, half-height y unless `isUniformScale` | [wiki]; [corpus] 294 non-square camera quads |
| 7 | `blendMode` 0 | SrcAlpha,One with texture alpha | colour premultiplied by vertex alpha, ONE,ONE, texture alpha only for the test | [wiki][rey][bc] |
| 8 | `alphaRef` | default 0, tested after erosion/soft | default 5; `clip(vertexA * texA - ref)` before erosion | [rey] declared default (1422 explicit 0s, no explicit 5); [bc] |
| 9 | `miscRenderFlags` 0x1 | ignored | depth test off (not for ground-layer decals) | [wiki][rey] DisableZBuffer; 2469 emitters |
| 10 | `pass` / draw order | `pass / 2` (14 and 15 merged) | phase (ground first) -> pass (monotonic compression) -> blend rank -> misc byte via render_priority + sorting_offset | [wiki] draw order |
| 11 | `colorLookUpTypeX/Y` | life on X (and on Y for type 3), middle row | 0 Constant / 1 Lifetime / 3 BirthRandom per particle row; default (age, 1) | [wiki]; 848 emitters use BirthRandom on Y |
| 12 | `SpawnShape` sphere / cylinder / box | volume always, flag 1 = "radial velocity", box size halved | flag 0x1 = fill, else surface; random shape turns also turn the velocity; box Size = half extents, +z face, quarter turns | [wiki] |
| 13 | `VfxPrimitiveRay` | width x2, length max(y, z) | width = x, length = y, start offset = z | [wiki][rey] |
| 14 | `lifetime` with a delay | emitted for `lifetime` after the delay | emission ends at `lifetime` on the system clock | [wiki] |
| 15 | `uvScale` / `uvRotation` / flips / `uvScrollClamp` | scale about 0, flip first, clamp = clamp the sample uv | scale/rotate about the centre, translate, flip last, inside the flipbook cell; clamp limits the birth ramp to -1..1 | [wiki][rey] |
| 16 | `texAddressModeBase`, `emitterUvScrollRate`, `uvMode` 2 | ignored / alpha lock off | wrap / mirror / clamp / border; system-time scroll; LockAlpha | [wiki][bc] SEPARATE_ALPHA_UV |
| 17 | `isLocalOrientation` false | turned with the effect's facing | axis-aligned spawn frame | [wiki] |
| 18 | `isDirectionOriented` on aquads / meshes, `rotation0` | ignored | +Z along travel (applied last); integrated spin x60 with `isRotationEnabled` | [wiki] |
| 19 | `disableBackfaceCull` | every mesh two-sided | meshes cull back faces unless set | [wiki] |
| 20 | particle shader | fresnel `pow(1-|N.V|)`, raised alpha; palette red only; distortion x0.15, untinted | exact fresnel / palette mixer / soft far fade / distortion / BGRA8 colour clamp / mesh saturate | [bc] |
| 21 | system `transform` | ignored | uniform scale applied (items 6655 x1.6, 6631 x1.1) | [wiki] |

## Remaining gaps (owner: vfx-runtime unless noted)

- `bindWeight` is binary (>= 0.5 follows); League follows translation by the weight, over age.
- `particleIsLocalOrientation`, `particleLingerType` 1/2, `emitterLinger`, `Linger` overrides, over-life `velocity`
  / `drag` / `acceleration`, `rateByVelocityFunction`, `useNavmeshMask`, stencil modes, `postRotateOrientationAxis`,
  mesh camera alignment, `FlexShapeDefinition` bound-object scaling.
- Trails: particles are not simulated as ribbon points (no velocity), `mCutoff`, the smoothing walk direction and
  `mBirthTilingSize.y` are not read.
- Erosion: the shader band formula is known, the CPU drive mapping is not; kept as the old threshold.
- `blendMode` 2 (Subtract, 51 emitters) is still additive; the palette row selection mapping is a guess.
- Troybin conversions (Flash, Barrier, LevelUp, summoner spells, melee-minion swing) remain approximate.
- Kits: `MissFortune_Base_W_buf`, `_W_MaxStart`, `_R_MuzzleFlash_Cas`, `Malphite_Base_W_buf_body`, `Ahri_Taunt`
  are fully disabled in League and no longer exist (kits-a/b may drop the calls).

<!-- AUTO: generated by tools/lol/vfx_coverage.py below this line -->

## Headline (weighted by play)

1083 of 1086 systems found in the raw bins (10 are troybin conversions), 15332 logged spawns, 267 distinct emitter/system fields.

| measure (share of weighted field uses) | value |
|---|---|
| extracted by tools/lol/extract_vfx.py | 97.1% |
| consumed by the runtime | 95.6% |
| semantics confirmed by external evidence | 81.3% |

## Open gaps ranked by impact (weighted uses x missing support)

| impact | uses (weighted) | field | state | values / features | evidence / note |
|---:|---:|---|---|---|---|
| 12153 | 12153 (1192) | `VfxEmitterDefinitionData.FlexShapeDefinition` | not extracted | VfxFlexShapeDefinitionData:1192 | scale by the bound object's size (weights ~1/200 -> ~1 for champions); not applied [wiki] |
| 10877 | 43508 (4166) | `VfxEmitterDefinitionData.particleLinger` | used, approx |  | linger: default 0 (vanish at stop) [wiki]; type 1/2 rewrites and emitterLinger not implemented |
| 10446 | 13057 (1060) | `VfxEmitterDefinitionData.particleIsLocalOrientation` | extracted, unused | True:1060 | particles turn live with the attachment [wiki]; not implemented |
| 10187 | 40749 (4122) | `VfxEmitterDefinitionData.bindWeight` | used, approx | ValueFloat:4122 const:3951, curve:159, curve+rand:3, rand:9 | translation follow weight over age; ours is binary (>= 0.5 rides along) [wiki] |
| 9999 | 39995 (3714) | `VfxEmitterDefinitionData.primitive` | used, approx | VfxPrimitiveArbitraryQuad:1525, VfxPrimitiveMesh:1386, VfxPrimitiveRay | camera quad / arbitrary quad (uv swap) / ray / mesh / attached mesh exact [wiki]; trails, beams and planar pro |
| 8324 | 8324 (838) | `VfxFlexShapeDefinitionData.scaleEmitOffsetByBoundObjectSize` | not extracted |  | scale by the bound object's size (weights ~1/200 -> ~1 for champions); not applied [wiki] |
| 6202 | 6202 (708) | `VfxFlexShapeDefinitionData.scaleBirthScaleByBoundObjectSize` | not extracted |  | scale by the bound object's size (weights ~1/200 -> ~1 for champions); not applied [wiki] |
| 4458 | 5573 (590) | `VfxEmitterDefinitionData.emitterLinger` | extracted, unused |  | linger: default 0 (vanish at stop) [wiki]; type 1/2 rewrites and emitterLinger not implemented |
| 4280 | 4280 (453) | `VfxAlphaErosionDefinitionData.erosionFeatherOut` | not extracted |  | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 3431 | 3431 (363) | `VfxEmitterDefinitionData.useNavmeshMask` | not extracted | True:363 |  |
| 3023 | 3023 (230) | `VfxAlphaErosionDefinitionData.erosionMapAddressMode` | not extracted | 0:228, 1:2 |  |
| 2456 | 3070 (284) | `VfxAlphaErosionDefinitionData.erosionSliceWidth` | extracted, unused |  | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 1869 | 7475 (264) | `VfxTrailDefinitionData.mBirthTilingSize` | used, approx | ValueVector3:264 const:263, curve:1 | ribbon through particles; mMode / tiling.x read; cutoff, smoothing walk, tiling.y not [wiki] |
| 1815 | 7261 (248) | `VfxTrailDefinitionData.mMode` | used, approx | 1:248 | ribbon through particles; mMode / tiling.x read; cutoff, smoothing walk, tiling.y not [wiki] |
| 1787 | 7149 (925) | `VfxEmitterDefinitionData.alphaErosionDefinition` | used, approx | VfxAlphaErosionDefinitionData:925 | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 1786 | 7143 (919) | `VfxAlphaErosionDefinitionData.erosionDriveCurve` | used, approx | ValueFloat:919 curve:905, curve+rand:1, const:13 | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 1778 | 7114 (916) | `VfxAlphaErosionDefinitionData.erosionMapName` | used, approx |  | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 1582 | 6330 (1013) | `VfxEmitterDefinitionData.isGroundLayer` | used, approx | True:1013 | ground-layer render phase; drawn as a terrain decal with depth bias [wiki] |
| 1500 | 6001 (190) | `VfxPrimitiveCameraTrail.mTrail` | used, approx | VfxTrailDefinitionData:190 | ribbon definition [wiki] |
| 1489 | 5957 (1018) | `VfxEmitterDefinitionData.textureMult` | used, approx | VfxTextureMultDefinitionData:1018 | second texture multiplied (its own uv transform partly read) |
| 1416 | 5664 (984) | `VfxTextureMultDefinitionData.textureMult` | used, approx |  | second texture multiplied (its own uv transform partly read) |
| 1159 | 4637 (659) | `VfxEmitterDefinitionData.depthBiasFactors` | used, approx |  | slope / constant bias; sign not established [wiki] |
| 962 | 3849 (630) | `VfxAlphaErosionDefinitionData.erosionMapChannelMixer` | used, approx | ValueColor:630 const:630 | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 918 | 918 (71) | `VfxFieldAccelerationDefinitionData.isLocalSpace` | not extracted | False:71 |  |
| 918 | 3671 (550) | `VfxTextureMultDefinitionData.birthUvScrollRateMult` | used, approx | ValueVector2:550 const:361, rand:185, curve:4 | second texture multiplied (its own uv transform partly read) |
| 903 | 3613 (427) | `VfxEmitterDefinitionData.birthOrbitalVelocity` | used, approx | ValueVector3:427 const:109, rand:308, curve:5, curve+rand:5 | rad/s revolving around the emitter origin; the orientation turn is not applied [wiki] |
| 842 | 842 (83) | `VfxFieldNoiseDefinitionData.radius` | not extracted | ValueFloat:83 const:83 |  |
| 787 | 787 (72) | `VfxFieldDragDefinitionData.radius` | not extracted | ValueFloat:72 const:72 |  |
| 738 | 2954 (280) | `VfxAlphaErosionDefinitionData.erosionFeatherIn` | used, approx |  | erosion band; shader exact [bc] but the CPU drive mapping is unverified |
| 725 | 725 (17) | `VfxEmitterDefinitionData.ParticlesShareRandomValue` | not extracted | True:17 |  |
| 670 | 670 (45) | `VfxFieldDragDefinitionData.Position` | not extracted | ValueVector3:45 const:45 |  |
| 655 | 2621 (155) | `VfxTrailDefinitionData.mSmoothingMode` | used, approx | 2:95, 1:60 | ribbon through particles; mMode / tiling.x read; cutoff, smoothing walk, tiling.y not [wiki] |
| 636 | 2545 (159) | `VfxTrailDefinitionData.mCutoff` | used, approx |  | ribbon through particles; mMode / tiling.x read; cutoff, smoothing walk, tiling.y not [wiki] |
| 592 | 2369 (242) | `VfxEmitterDefinitionData.fieldCollectionDefinition` | used, approx | VfxFieldCollectionDefinitionData:242 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 476 | 793 (62) | `VfxEmitterDefinitionData.Linger` | used, semantics unknown | VfxLingerDefinitionData:62 |  |
| 473 | 1892 (374) | `VfxTextureMultDefinitionData.birthUVOffsetMult` | used, approx | ValueVector2:374 rand:256, const:110, curve:8 | second texture multiplied (its own uv transform partly read) |
| 446 | 446 (27) | `VfxPrimitiveMesh.AlignYawToCamera` | not extracted | True:27 |  |
| 445 | 445 (26) | `VfxPrimitiveMesh.AlignPitchToCamera` | not extracted | True:26 |  |
| 445 | 445 (26) | `VfxPrimitiveMesh.6aec9e7a` | not extracted | True:26 |  |
| 438 | 730 (54) | `VfxLingerDefinitionData.SeparateLingerColor` | used, semantics unknown | ValueColor:54 curve:30, const:24 |  |
| 410 | 513 (53) | `VfxSystemDefinitionData.overrideScaleCap` | extracted, unused |  |  |
| 384 | 1534 (76) | `VfxPrimitiveArbitraryTrail.mTrail` | used, approx | VfxTrailDefinitionData:76 | ribbon definition [wiki] |
| 361 | 361 (40) | `VfxEmitterDefinitionData.rateByVelocityFunction` | not extracted | ValueVector2:40 const:40 |  |
| 332 | 332 (22) | `VfxPaletteDefinitionData.PaletteTextureAddressMode` | not extracted | 2:22 |  |
| 312 | 312 (38) | `VfxEmitterDefinitionData.drag` | not extracted | ValueVector3:38 curve:32, const:6 |  |
| 268 | 1073 (102) | `VfxFieldCollectionDefinitionData.fieldNoiseDefinitions` | used, approx |  | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 268 | 1073 (102) | `VfxFieldNoiseDefinitionData.axisFraction` | used, approx | [1.0, 1.0, 1.0]:67, [2.25, 0.0, 2.25]:12, [9.0, 8.0, 9.0]:4, [5.0, 5.0 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 262 | 262 (52) | `VfxEmitterDefinitionData.stencilRef` | not extracted | 1:30, 3:8, 33:7, 7:3 |  |
| 262 | 262 (17) | `VfxEmitterDefinitionData.useEmissionMeshNormalForBirth` | not extracted | False:17 |  |
| 258 | 1032 (68) | `VfxTextureMultDefinitionData.texDivMult` | used, approx | [2.0, 2.0]:39, [0.5, 0.5]:8, [1.0, 0.5]:4, [0.5, 1.0]:4 | second texture multiplied (its own uv transform partly read) |
| 242 | 242 (38) | `VfxEmitterDefinitionData.stencilMode` | not extracted | 3:28, 2:8, 1:2 |  |
| 233 | 933 (77) | `VfxFieldCollectionDefinitionData.fieldAccelerationDefinitions` | used, approx |  | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 220 | 879 (80) | `VfxFieldCollectionDefinitionData.fieldDragDefinitions` | used, approx |  | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 218 | 871 (72) | `VfxFieldAccelerationDefinitionData.acceleration` | used, approx | ValueVector3:72 const:72 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 210 | 842 (83) | `VfxFieldNoiseDefinitionData.frequency` | used, approx | ValueFloat:83 const:83 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 196 | 784 (243) | `VfxTextureMultDefinitionData.uvScaleMult` | used, approx | ValueVector2:243 const:228, curve:14, curve+rand:1 | second texture multiplied (its own uv transform partly read) |
| 192 | 769 (74) | `VfxFieldNoiseDefinitionData.velocityDelta` | used, approx | ValueFloat:74 curve:3, const:71 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 191 | 765 (71) | `VfxFieldDragDefinitionData.strength` | used, approx | ValueFloat:71 const:69, rand:2 | acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read [wiki] |
| 170 | 213 (51) | `VfxTextureMultDefinitionData.texAddressModeMult` | extracted, unused | 2:49, 3:2 | second texture multiplied (its own uv transform partly read) |
| 163 | 653 (164) | `VfxTextureMultDefinitionData.ParticleIntegratedUvScrollMult` | used, approx | IntegratedValueVector2:164 const:72, curve:89, rand:3 | second texture multiplied (its own uv transform partly read) |
| 163 | 163 (25) | `VfxAlphaErosionDefinitionData.erosionDriveSource` | not extracted | 1:25 |  |
| 161 | 161 (29) | `VfxTextureMultDefinitionData.birthUvRotateRateMult` | not extracted | ValueFloat:29 rand:3, const:26 |  |
| 161 | 161 (26) | `VfxEmitterDefinitionData.emissionMeshScale` | not extracted | 0.9:4, 0.7:4, 1.1:4, 2.0:2 |  |
| 160 | 160 (6) | `VfxLingerDefinitionData.UseSeparateLingerColor` | not extracted | True:6 |  |
| 158 | 158 (61) | `VfxEmitterDefinitionData.cb13aff1` | not extracted |  |  |
| 136 | 543 (41) | `VfxChildIdentifier.effectKey` | used, approx | hash:79817e8f:5, hash:ce04069f:5, hash:cdd38944:4, hash:9fc66f72:3 | child system per particle (birth children follow their particle) [wiki] |
| 135 | 541 (39) | `VfxEmitterDefinitionData.childParticleSetDefinition` | used, approx | VfxChildParticleSetDefinitionData:39 | child system per particle (birth children follow their particle) [wiki] |
| 135 | 541 (39) | `VfxChildParticleSetDefinitionData.childrenIdentifiers` | used, approx |  | child system per particle (birth children follow their particle) [wiki] |
| 126 | 157 (49) | `VfxEmitterDefinitionData.isFollowingTerrain` | extracted, unused | True:49 |  |
| 125 | 501 (65) | `VfxMeshDefinitionData.mLockMeshToAttachment` | used, approx | True:65 | skinned overlay of the host (submesh masks partly read) [wiki] |

## Done / confirmed fields

| uses (weighted) | field | json | evidence |
|---:|---|---|---|
| 92133 | `ValueVector3.probabilityTables` | value | value container: curves + probability tables baked per field [wiki] |
| 69988 | `VfxEmitterDefinitionData.texture` | tex | texture path |
| 69987 | `VfxEmitterDefinitionData.rate` | rate rate_ec | particles/s on the emitter phase; isSingleParticle = one burst of `rate` [wiki] |
| 69010 | `VfxEmitterDefinitionData.particleLifetime` | plife plife_q | seconds, emitter phase; negative = never expires [wiki] |
| 68872 | `VfxEmitterDefinitionData.birthScale0` | bscale bscale_ec bscale_q | camera quad half-extents x/y (non-uniform), aquad half-extents, ray width/length/offset, mesh multiplier [wiki][corpus] |
| 60413 | `ValueColor.curve(times>1)` | value | value container: curves + probability tables baked per field [wiki] |
| 59929 | `VfxEmitterDefinitionData.blendMode` | blend | 0 Add (colour premultiplied, ONE,ONE), 1 Alpha, 3 None (depth write), 4 AlphaAdd, 5 Premul [wiki][rey][bc]; 2 Subtract s |
| 56908 | `VfxEmitterDefinitionData.lifetime` | life | emission END time on the system clock, measured from the system start [wiki] |
| 56646 | `ValueVector3.curve(times>1)` | value | value container: curves + probability tables baked per field [wiki] |
| 55941 | `VfxEmitterDefinitionData.Color` | color bcolor | Color x birthColor, BGRA8-clamped [wiki][bc] |
| 51525 | `VfxEmitterDefinitionData.scale0` | scale bscale | camera quad half-extents x/y (non-uniform), aquad half-extents, ray width/length/offset, mesh multiplier [wiki][corpus] |
| 44739 | `VfxEmitterDefinitionData.pass` | pass | draw order: phase (ground layer first), pass, blend rank, miscRenderFlags [wiki] |
| 44668 | `VfxEmitterDefinitionData.birthRotation0` | brot brot_q | Euler degrees composed Z, then X, then Y; camera quads roll by X [wiki][rey][corpus] |
| 41641 | `VfxEmitterDefinitionData.isSingleParticle` | single | particles/s on the emitter phase; isSingleParticle = one burst of `rate` [wiki] |
| 41595 | `VfxEmitterDefinitionData.birthColor` | bcolor bcolor_ec bcolor_q | Color x birthColor, BGRA8-clamped [wiki][bc] |
| 37765 | `VfxEmitterDefinitionData.SpawnShape` | shape | sphere/cylinder radius along X (filled with flag 0x1) + random turns; box half extents, +z face or filled, quarter turns |
| 37279 | `VfxEmitterDefinitionData.isUniformScale` | uniform | X used for every axis [wiki] |
| 31035 | `VfxEmitterDefinitionData.EmitterPosition` | pos | League units -> m (x0.01), z mirrored; base of the birth position [wiki] |
| 24578 | `ValueFloat.probabilityTables` | value | value container: curves + probability tables baked per field [wiki] |
| 23435 | `VfxEmitterDefinitionData.birthVelocity` | bvel bvel_ec bvel_q | units/s in the emitter frame, turned by the SpawnShape rotation [wiki] |
| 21602 | `VfxEmitterDefinitionData.miscRenderFlags` | misc | bit 0x1 DisableZBuffer = depth test off (not on ground-layer decals) [wiki][rey] |
| 17299 | `VfxEmitterDefinitionData.texDiv` | texdiv | flipbook cell = (col + uv) / cols, row-major from top-left; loop of numFrames from startFrame [wiki][bc] |
| 14814 | `VfxEmitterDefinitionData.birthDrag` | drag drag_q | per-axis damping 1/s [wiki] |
| 14713 | `VfxEmitterDefinitionData.alphaRef` | alpha_ref | default 5; clip(vertexA * texA - ref), 0 = off [wiki][rey][bc] |
| 12805 | `VfxSystemDefinitionData.complexEmitterDefinitionData` | emitters | complex emitters run the full simulation [wiki] |
| 12780 | `ValueFloat.curve(times>1)` | value | value container: curves + probability tables baked per field [wiki] |
| 12683 | `ee39916f.emitOffset` | shape | legacy offset + one turn per emitRotationAngles entry, in order [wiki] |
| 12500 | `VfxEmitterDefinitionData.timeBeforeFirstEmission` | delay | delay before the first emission, system clock [wiki] |
| 12074 | `VfxEmitterDefinitionData.particleColorTexture` | ctex | lookup drivers 0 Constant / 1 Lifetime / 2 Velocity (approx: offset) / 3 BirthRandom; defaults (age, 1); clamped; droppe |
| 12070 | `VfxEmitterDefinitionData.birthUvScrollRate` | uvrate uvrate_q | birth ramp offset + age*rate wrapped / clamped (-1..1); integrated scroll unclamped [wiki][rey] |
| 11920 | `VfxShapeLegacy.emitRotationAngles[ValueFloat:rand]` | shape | legacy offset + one turn per emitRotationAngles entry, in order [wiki] |
| 11765 | `VfxEmitterDefinitionData.numFrames` | frames | flipbook cell = (col + uv) / cols, row-major from top-left; loop of numFrames from startFrame [wiki][bc] |
| 10534 | `VfxEmitterDefinitionData.isRandomStartFrame` | rand_frame | flipbook cell = (col + uv) / cols, row-major from top-left; loop of numFrames from startFrame [wiki][bc] |
| 10455 | `VfxPrimitiveMesh.mMesh` | mesh | static particle mesh (.scb); culls back faces unless disableBackfaceCull [wiki] |
| 10432 | `VfxMeshDefinitionData.mSimpleMeshName` | mesh | static particle mesh (.scb); culls back faces unless disableBackfaceCull [wiki] |
| 10377 | `VfxEmitterDefinitionData.disableBackfaceCull` | disable_cull | static particle mesh (.scb); culls back faces unless disableBackfaceCull [wiki] |
| 10318 | `VfxEmitterDefinitionData.isLocalOrientation` | lorient | false: spawn frame axis aligned (only the system position) [wiki] |
| 9832 | `VfxEmitterDefinitionData.colorLookUpTypeY` | clut | lookup drivers 0 Constant / 1 Lifetime / 2 Velocity (approx: offset) / 3 BirthRandom; defaults (age, 1); clamped; droppe |
| 9831 | `VfxEmitterDefinitionData.birthRotationalVelocity0` | rotvel rotvel_q | Euler degrees composed Z, then X, then Y; camera quads roll by X [wiki][rey][corpus] |
| 9658 | `ValueVector2.probabilityTables` | value | value container: curves + probability tables baked per field [wiki] |
| 9009 | `VfxShapeLegacy.emitRotationAngles` | shape | legacy offset + one turn per emitRotationAngles entry, in order [wiki] |
| 9001 | `VfxShapeLegacy.emitRotationAxes` | shape | legacy offset + one turn per emitRotationAngles entry, in order [wiki] |
| 8975 | `VfxShapeLegacy.emitOffset` | shape | legacy offset + one turn per emitRotationAngles entry, in order [wiki] |
| 7670 | `VfxEmitterDefinitionData.birthUVOffset` | uvoff | (uv - centre) * scale, rotate, + centre + translation, flip; inside the cell [wiki][rey] |
| 7118 | `VfxEmitterDefinitionData.worldAcceleration` | accel | world-axis acceleration (integrated twice) [wiki] |
| 5888 | `VfxEmitterDefinitionData.isDirectionOriented` | dir | camera quads stretch y along screen velocity; aquads / meshes +Z along travel, applied last [wiki] |
| 5816 | `VfxEmitterDefinitionData.softParticleParams` | soft soft_in | smoothstep fade-in (beginIn, deltaIn) minus optional far fade [wiki][bc] |
| 5509 | `VfxSoftParticleDefinitionData.deltaIn` | soft_in | smoothstep fade-in (beginIn, deltaIn) minus optional far fade [wiki][bc] |
| 4210 | `VfxEmitterDefinitionData.uvScale` | uvscale | (uv - centre) * scale, rotate, + centre + translation, flip; inside the cell [wiki][rey] |
| 4156 | `VfxEmitterDefinitionData.isRotationEnabled` | rotint | integrated spin rate in degrees per 1/60 s, needs isRotationEnabled [wiki] |
| 3981 | `VfxShapeBox.flags` | shape | sphere/cylinder radius along X (filled with flag 0x1) + random turns; box half extents, +z face or filled, quarter turns |
| 3825 | `ValueColor.probabilityTables` | value | value container: curves + probability tables baked per field [wiki] |
| 3180 | `VfxEmitterDefinitionData.disabled` | @gate | load-time gate: dropped [wiki] |
| 3033 | `VfxEmitterDefinitionData.paletteDefinition` | palette | u = sat(dot(tex, mixer)); rgb replaced, alpha = tex.a [bc]; row selection approx |
| 2905 | `VfxEmitterDefinitionData.uvMode` | uvmode | uvMode 2 LockAlpha: alpha at the un-translated uv [wiki][bc] (1 ScreenSpace not implemented) |
| 2533 | `VfxPaletteDefinitionData.paletteTexture` | palette | u = sat(dot(tex, mixer)); rgb replaced, alpha = tex.a [bc]; row selection approx |
| 2498 | `VfxShapeCylinder.radius` | shape | sphere/cylinder radius along X (filled with flag 0x1) + random turns; box half extents, +z face or filled, quarter turns |
| 2386 | `VfxEmitterDefinitionData.directionVelocityScale` | dvs | stretch max(min, speed * scale) [wiki] |
| 2352 | `VfxEmitterDefinitionData.emitterUvScrollRate` | emuv | system-time scroll after the flips (quads) [wiki] |
| 2343 | `VfxEmitterDefinitionData.frameRate` | fps | frames/s x birthFrameRate; 0 = static frame [wiki] |

## Most-played systems (sim spawn counts)

| spawns | system |
|---:|---|
| 748 | SRU_OrderMinionRanged_Base_BA_Mis |
| 500 | MissFortune_Base_E_Bullet_Child |
| 500 | MissFortune_Base_E_Child_Bullet_Dirt |
| 437 | SRU_ChaosMinionRanged_Base_BA_Mis |
| 336 | MissFortune_Base_R_mis_child_01 |
| 298 | SRU_OrderMinionRanged_Base_BA_Tar |
| 224 | MissFortune_Base_R_mis |
| 219 | SRU_ChaosMinionRanged_Base_BA_Tar |
| 137 | MissFortune_Base_BA_Tar |
| 136 | Sona_Base_R_Tar_child |
| 133 | LevelUp_glb |
| 120 | Ahri_Base_BA_cas_fingertips |
| 120 | Ahri_Base_BA_mis |
| 109 | Yasuo_base_BA_trail_1 |
| 104 | SRU_OrderMinionSiege_Base_SRU_Order_CanM_BA1 |
| 98 | Turret_Skin25_BA |
| 95 | Global_Slow |
| 94 | MissFortune_Base_P_Mis |
| 86 | MissFortune_Base_BA_cas |
| 86 | SRU_OrderMinionSiege_Base_SRU_Order_CanM_Tar |
| 85 | MissFortune_Base_BA_cas_left |
| 84 | MissFortune_Base_P_Tar |
| 84 | Ahri_Base_W_mis_02 |
| 77 | MissFortune_Base_BA_mis |
| 74 | Ezreal_Base_BA_cas |

Systems not found in the raw bins (legacy troybin conversions): Global_SS_Flash, Global_SS_Flash_02, Global_SS_Barrier, LevelUp_glb, SRU_Order_MM_BA1_cas, Global_SS_Heal, Global_SS_Heal_02, Global_SS_Clarity, Global_SS_Cleanse, Global_SS_Ghost
