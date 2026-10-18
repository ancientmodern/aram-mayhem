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
- [vfx] Missing child particle systems, animated-mesh emitters, bone attachment (needs socket API) and
  distortion/refraction.
- [vfx] Palettes, fresnel/reflection, falloff textures, emission rate curves, linger, timeBeforeFirstEmission and
  isSingleParticle semantics need auditing against the bins.
- [vfx] Missile visuals: heights, trail ribbons, orientation, impact effects at the hit bone.
- [vfx] Overall intensity, size and timing need calibration against reference footage of each spell.

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
- [hud] The HUD is a generic approximation. Rebuild it from League's own HUD textures and layout (bottom champion
  panel, ability frames, cooldown sweeps, rank pips, level-up buttons, item slots, gold, stat panel, summoners,
  XP ring, buffs, minimap frame and icons, top score, Tab scoreboard, kill feed, announcements, death timer).
- [hud] The shop is "very hard to use". Replicate League's shop: recommended tab, categorized list, search,
  build tree (builds from/into with cost), buy/sell/undo, hotkeys, right-click buy, tooltips.
- [hud] Remove augment UI (augments disabled via Rules.AUGMENTS_ENABLED).

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
