# Fidelity gaps vs. live League of Legends (ARAM, Howling Abyss)

Player verdict after the first real playtest: visuals and motion feel "PS1 vs PS5" next to League.
Rule for every decision: **when unsure, compare with original League** — the game files in
`D:\Riot Games\League of Legends\Game` (bins, textures, UI, animation graphs; parse with `tools/lol/*`),
the League wiki, and real gameplay screenshots/videos. Never guess when the data exists.

Owner tags: [motion] [vfx] [world-ui] [hud] [env] [kits-a] [kits-b]

## Characters & motion
- [motion] Animation state machine is ad-hoc: League's AnimationGraphData (per champion bin) defines clips, blend
  times, idle variants, run/haste variants, attack variants & crit, spell clips per slot, channel loops,
  "run in/out" and turn behaviour. Read it and drive anims from it.
- [motion] Attack windup/cast point must come from data (attackDelayCastOffsetPercent, attack total time); spell
  cast frames (castFrame / mCastTime) must line up with the animation's release frame.
- [motion] Missiles and VFX start at the origin, not at bones. League spawns them at named bones
  (weapon/hand/barrel, `C_BUFFBONE_GLB_*`). Need `Unit.socket(bone_name) -> Node3D` (BoneAttachment3D, case-
  insensitive with fallbacks) and `Unit.missile_origin()`.
- [motion] Turning, accel and stop: League turns very quickly, there is no sliding, and the run anim speed matches
  move speed. Check foot sliding.
- [motion] Units pass through each other. League has unit collision radii (gameplayRadius) and pathing around
  other units; minions jostle and champions are body-blocked by minions.
- [motion] Death: the body stays down for the respawn period (champions); minions play death then fade or sink.
- [motion] Brush: a unit in brush becomes semi-transparent for its own team.
- [motion] Character shading looks flat and dull next to League (rim and self-illum constants are guesses).
  Compare with screenshots.

## VFX
- [vfx] Done: probability tables (inverse-CDF), emitter-time birth curves, isSingleParticle = burst of `rate`,
  legacy emit offsets/rotation angles, radial sphere/cylinder velocity, orbital velocity, fields, uv rotation /
  clamp / uvMode 2, rate curves, particleLinger + linger colour, child systems, attached-mesh shells, distortion,
  fresnel/falloff, mesh vertex colours, depth bias, rays, planar projections, missile frame (+Y = flight),
  League missile heights + hit bones, sockets for casts/CC, trails tiled by distance. Central updater + load-time
  prebuild (spawn ~0.1-0.3 ms).
- [vfx] Open: palettes (paletteDefinition), per-particle birth UV offset, isLocalOrientation, VfxShapeSphere/Box
  flag semantics beyond "radial", troybin conversion is approximate (Flash/Barrier/LevelUp), Map12 snow texture is
  near-black (stays disabled), size/brightness calibration only spot-checked (Ezreal W ring, Lux Q rings).

## World UI & feedback
- [world-ui] Health bars are flat rects. League's have textured frames, 100-HP tick marks, a level box, shield
  segments, a mana bar and team colours, and minion/structure variants. Use League UI textures.
- [world-ui] Floating combat text: League fonts, colours (physical, magic, true, crit, heal, gold) and pop/arc
  motion.
- [world-ui] Turret range is a low-poly filled octagon. League draws a thin ring only when near an enemy turret,
  plus a turret aggro indicator.
- [world-ui] Cursors: League hardware cursors (normal, attack, ally, ability targeting).
- [world-ui] Hover outline (red enemy / blue ally silhouettes), attack range ring (C key / A key), spell
  indicators from League textures, level-up effect, gold popups.

## HUD & shop
- [hud] Done: HUD rebuilt from League's own UI bins + atlases (tools/lol/extract_hud.py -> assets/ui/hud/layout.json,
  tex/, icons/, minimap_map12.png); src/ui/hud.gd draws every element at League's position/anchor/UV via
  src/ui/hud/hud_layout.gd. Shop rebuilt from the ItemShop layout (src/ui/shop_panel.gd). Augment UI removed.
- [hud] Still below League: EffectAnimation sprite sheets (glint/sheen/level-up/item-complete FX) are not played
  (frame counts sit in unnamed bin fields); ~55 standalone UI textures (e.g. the HUD gold button, Shop_Button*)
  are referenced by hash only and could not be resolved (gold bar from clarity_hudatlas used instead); TextData
  font descriptions are links to entries we could not find, so sizes/colours are chosen by eye; minimap bounds
  (-28,-19)-(12849,12858) are Riot's published Map12 values, not read from map12.bin; no target frame, no pings,
  no chat, no item-set tab, no drag-to-sell; buffs without an icon fall back to the source champion's art.

## Environment
- [env] Fixed: turret side "walls" were rubble submeshes, now hidden.
- [env] Turret damage states (State1-3 submeshes), destruction and rubble; nexus/inhib idle animations.
- [env] Map ambient VFX from the map bins (snow, braziers, crystals, waterfalls), animated props and poros.
- [env] Unit shadows on the map (the map shader is lightmapped and does not receive shadows), lighting and
  grade match.
- [env] Camera: League's FOV, pitch, distance, zoom range and smoothing.

## Kits
- [kits-a/b] Audit every champion for bugs and live-League behaviour (e.g. Ezreal W mark not detonating or its VFX
  never cleared).
