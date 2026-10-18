# Spatial calibration audit (camera, scale, ranges)

Owner: [spatial] agent, 2026-10-18. Player verdict: the camera feels too close and should be higher; Miss Fortune's
ranges look absurdly long; turret and relic ranges look wrong. These turned out to be one problem with three causes:

1. **The camera was about 15% too close.** It used FOV 40 at 2250 units and showed 1638 units vertically through the
   focus. League ARAM shows about 1890. Because of this, every range, ring and model looked about 15% bigger on screen.
2. **Range rules were wrong.** Every unit-targeted spell measured edge to edge, adding about 130 units. Every spell
   ring added the caster's radius (65). MF Q used its display-only override (650) as its gameplay range. Together,
   MF Q reached 780 units centre to centre where League's is 680.
3. **The relic heal indicator art was scaled 2.48x.** That drew its ring at about 1460 units, but the heal radius is
   850.

Units: League units = cm; world metres = units / 100 (`G.U`).

## 1. Camera

### Evidence

- **League data.** In `Global.wad.client`, the globals bin (`2f30c6f7747eb925`) holds `CameraConfig_*` objects.
  - `CameraConfig_ARAM` and `CameraConfig_KIWI` (ARAM Mayhem) both set the field hash `0x83fa5f0d` to **50.0**.
    That hash resolves to **`ZoomFov`** by FNV-1a dictionary attack. It is not in the CDragon lists.
  - `CameraConfig_CLASSIC` does not set it, so classic uses the engine default.
  - `mZoomMaxDistance` is set only for ODYSSEY (2600) and DARKSTAR (3000). ARAM and classic use the engine default,
    which is not in data: the exe is packed.
  - Trapezoids are shared by all modes (semi-lock / elastic clamp: `mMaxXTop 800`, `mMaxXBottom 650`,
    `mMaxZUp -600`, `mMaxZDown 400`).
  - `DynamicCameraSettings` has `DownCameraAngle` = 55.
  - The Riot Replay API and League Director give no defaults (fieldOfView etc. are only live values).
- **Measurement 1: range-ring fit.** Frame `Fhc7HWAdA38` (YouTube auto-frame `maxres2`, 1280x720) is an ARAM game
  where the Brand player aims W.
  - The 900-unit Brand W range ring was traced: 273 edge pixels.
  - A pinhole camera was fitted to it (`scratchpad/sp/ringfit.py`), giving rms 2.1-2.4 px.
  - **Pitch = 55.4-56.0 whatever the FOV. Vertical view span through the focus = 1886-1896 units.**
  - At FOV 50 the fit gives pitch **56.0** and distance **2022**.
  - A 965-unit ring (range + radius) would mean a span of 2030 units, which contradicts measurement 2. So League
    draws spell rings at castRange, which confirms the ring fix in section 3.
- **Measurement 2: image registration.** Frame `9FucHCjl4ao` (ARAM Mayhem, Chaos outer turret at max zoom; the
  minimap camera box is the same size in three frames from two videos, so this is max zoom).
  - Our map was rendered with the turret pinned to the same pixel (`src/debug/spatial_probe.gd`).
  - Edge maps were matched by normalised cross-correlation over scale and translation (`scratchpad/sp/match*.py`).
  - Old camera: best scale **0.85-0.86**, so League shows 16% more. New camera: best scale **0.975**.
  - The FOV itself is only weakly constrained by perspective in both measurements. The data value (50) decides it.

### Camera values

| Value | Ours (old) | League | Source | Fixed |
|---|---|---|---|---|
| Vertical FOV | 40 | **50** (ARAM / Mayhem) | `CameraConfig_ARAM/KIWI.ZoomFov` | yes |
| Pitch | 56 | **56.0** (fit at FOV 50; 55.4-56 at any FOV) | ring fit | kept |
| Eye-to-focus distance at max zoom | 2250 | **~2020** (span 1886 / (2 tan 25)) | ring fit + registration | yes (20.2 m) |
| Vertical span through focus | 1638 | **1886-1932** | both measurements | yes: 1884 |
| Ground footprint, top x bottom x depth (units) | 3860 x 2338 x 2102 | 4886 x 2548 x 2522 (new) | probe | yes |
| Min zoom | 1500 (guess) | not in data | - | 1350 (same 2:3 ratio) |
| Zoom steps | 1.25 m, ~6 notches | not in data | - | 1.1 m, ~6 notches |
| Start zoom | max | max | footage | kept |
| Projection | perspective, keep height | perspective, vertical FOV | ultrawide shows more horizontally | kept |
| Locked focus | champion feet | champion centred | no counter-evidence (frames were unlocked) | kept |
| Yaw | 0 | 0 | the lane diagonal matches in the overlay | kept |

### Champion size on screen

These are the lead's numbers, at default max zoom, champion at screen centre, `unit.height` feet to top, from
`spatial_probe.gd`.

| Champion | Old 1080p | Old 1440p | New 1080p | New 1440p |
|---|---|---|---|---|
| Miss Fortune (1.60 m) | 63 px | 84 px | **55 px** | **73 px** |
| Yasuo (2.07 m) | 78 | 104 | 67 | 89 |
| Leona (2.17 m) | 81 | 108 | 71 | 95 |
| Gameplay radius 65 u | 43 | 57 | 37 | 49 |

The League equivalent is the new column within 2%: the League span is 1886-1932 units against our new 1884.

Direct model check against the real frame: the Chaos outer turret, same position and 720p, measures about 210-220 px
tall in League and 210 px in ours with the new camera. Ours was about 225 px with the old camera, and its
surroundings were 15% bigger. The old camera magnified champions about 14%, which the player read as "low-poly" on
the 512 px textures.

### Screenshots inspected

- `spnew/f0_fov50_p56_d2020.png` and `f0_fov40_p56_d2250.png`, beside the League frame, are in
  `scratchpad/sp/cmp_new.jpg`. The braziers, ground emblems, plank and bridge walls line up with League with the new
  camera. With the old one everything is about 15% bigger.
- `splane/*.png` (2560x1440, default camera on MF in lane) is in `scratchpad/sp/lane_cmp.jpg`.

## 2. Scale (League units to metres)

| Item | Ours | League | Fixed |
|---|---|---|---|
| Map mesh | `extract_map_geo.py` S = 0.01, (x, y, -z) | same | ok |
| Unit and structure positions | `G.lol_pos` x 0.01 | same | ok |
| Outer turret to outer turret | 40.93 m | 4093 u ((4943,4929) to (7885,7774)) | ok |
| Character meshes | `export_character.py` S = 0.01 x skinScale | same | ok |
| Gameplay radii, ranges, missile speeds | x `G.U` everywhere (`missileSpeed * G.U`) | - | ok |
| Range ring textures | ring at the quad edge (circularrangeindicator 7/1024 px from the edge) | - | ok |

No double conversions were found.

## 3. Range rules

| Rule | Ours (old) | League | Source | Fixed |
|---|---|---|---|---|
| Basic attack | range + own radius + target radius (edge) | edge | wiki Range: "Basic attacks always use edge range" | ok |
| Attack range ring | range + own radius | same | - | ok |
| Unit-targeted spell reach | castRange + both radii, always | **centred**, unless `castRangeUseBoundingBoxes` | wiki Range; bin flag (MF Q is the only roster spell with it) | **yes** (`Ability.in_cast_range`, `range_edge`) |
| `castRangeDisplayOverride` on unit-targeted spells | used as gameplay range | display only | MF Q: castRange 550, override 650 | **yes** (`display_range`) |
| Spell ring radius | castRange + caster radius | castRange (override if set; + own radius only for edge spells) | ring fit above | **yes** (`Ability.indicator_range_m`) |
| Skillshot / ground spells | override = reach | same (Ezreal Q 1150, Lux Q 1175...) | - | ok |

## 4. Champion values (League bins: `Champions/<X>.wad.client`, effective values from `src/debug/spatial_ranges.gd`)

Notes:

- AR = attack range; ring = AR + gameplay radius (League: 65, Annie and Veigar 55, Malphite 80, from
  `overrideGameplayCollisionRadius`).
- Line widths: League `mLineWidth` is a half-width, so we store width = 2 x mLineWidth.

| Champion | AR | Q | W | E | R | Fixed |
|---|---|---|---|---|---|---|
| Miss Fortune | 550 | **550 edge (680 c-c), ring 650**. Was 650 + radii = 780 c-c, ring 715 | self | 1000, r 350 (ring was 1065) | cone 1400, 2 x 17 deg | **yes** |
| Ahri | 550 | 970, w 200 | ring 700 (override) | 975, w 120 | dash 500 (data override 450) | ring only |
| Annie | 625 | 625 c-c (was 745) | 600, cone 2 x 24.8 | 800 c-c | 600, r 250 | **yes** |
| Darius | 175 | r 425 | 300 | 535, cone 50 | **475 c-c, ring 460** (was 460 + radii = 590) | **yes** |
| Ezreal | 550 | 1150, w 120 | 1150, w 120 | 475 | 3000 shown, w 320 | ok |
| Garen | 175 | self | self | r 325 | 400 c-c (was 530) | **yes** |
| Jinx | 525 | self | 1450, w 120 | 925 | w 280 | ok |
| Leona | 125 | self | r 450 | 875, w 140 (League mLineWidth 80, so 160) | 1200, r 325 | E width noted |
| Lux | 550 | 1175, w 140 (League 160) | 1150, w 220 (League 300) | 1100, r 310 | 3340, w 380 | widths noted |
| Malphite | 125 | 625 c-c (was 770) | self | r 400 | 1000, r 325 | **yes** |
| Master Yi | 175 | 600 c-c (was 730) | self | self | self | **yes** |
| Sona | 550 | 825 | 1000 | 400 (League override 430) | 1000 travel, ring 900, w 280 | ok |
| Veigar | 550 | 1000, w 140 | 950, r 240 | 725, r 390 | 650 c-c (was 770) | **yes** |
| Yasuo | 175 | 475, w 100 (League 110) | 400 | 475 c-c (was 605) | 1400 | **yes** (E) |

"Noted" widths are indicator half-widths from the bin. The missile hitbox widths were not re-verified, so they are
left for the kit owner.

## 5. Structures, relic, summoners, minions

| Value | Ours (old) | League | Source | Fixed |
|---|---|---|---|---|
| Turret attack range | 750 | 750 | `Map12 HA_Outer/HA_Nexus attackRangeModifiable` | ok |
| Turret gameplay radius | 110 | **88.4** | `overrideGameplayCollisionRadius` | **yes** (ring 860 -> 838) |
| Fountain (shrine) range | 1250 | **1100** (acquisition 1200) | `HA_AP_OrderShrineTurret` | **yes** |
| Relic trigger radius | 150 | 150 | `Map12/Spells/HowlingAbyssRelicAura_AOE TriggerRadius` | ok |
| Relic heal radius (gameplay) | 850 | 850 | `HealingRadius` | ok |
| Relic heal indicator / pulse art | 2.48x, ring at about **1460 u** | ring at 850 | ring texture peak 0.84-0.88 of quad half-extent 685 = 590 u | **yes**, scale 1.45 (ring 832-867) |
| Flash / Mark / Ignite / Heal / Clarity | 400 / 1600 / 600 / 850 / 600 | same | - | Ignite now centred |
| Minion range (melee/caster/siege/super) | 110 / 550 / 300 / 170 | same | - | ok |
| Minion gameplay radius | 48 (siege/super 65) | 48 / 65 | - | ok |
| Hexgate | entry 1.9 m, reposition 250 u | from `extract_hexgate.py` | - | not re-audited |

## Files changed

- `src/player/camera_rig.gd`: FOV 50, max zoom 20.2, min 13.5, step 1.1.
- `src/core/ability.gd`: `range_edge`, `display_range`, `indicator_range_m`, centred `in_cast_range`.
- `src/champions/champion_kit.gd`: `init_ability` reads `castRangeUseBoundingBoxes` and treats the override as
  display-only for unit-targeted spells.
- `src/player/player_controller.gd`: spell ring radius.
- `data/champions/missfortune_game.json`: flag added.
- `src/core/turret.gd`: radius and fountain range.
- `src/match/relic.gd`: `AOE_SCALE`.
- New debug harnesses: `src/debug/spatial_probe.gd` and `src/debug/spatial_ranges.gd`.

## Open items

- **HUD minimap camera box:** League draws an axis-aligned rectangle of about 4420 x 2320 units at max zoom (59 x
  30 px on a 172 px map at 720p). Ours draws the frustum trapezoid.
- **Turret model:** the League frame's turret looks a little taller and thicker than ours at the same spot. The cause
  could be the ARAM Mayhem variant or model scale; it needs checking by the env / model owner.
- **Kit indicator widths:** Lux Q/W, Leona E, Yasuo Q differ from 2 x mLineWidth; needs checking by the kit owner.
