# Timing audit (cast times, windups, missile speeds, delays)

Owner: [timing] agent, 2026-10-18. Player report: ranges are fine now, but missile speeds are off (Jinx W "far too fast").
Units: League units per second (u/s) for speeds, seconds for times. Our engine converts with `G.U` = 0.01 (m).

## Method and rules found in the data

Raw bins: `Champions/<X>.wad.client` `data/characters/<x>/<x>.bin`, read by `tools/lol/extract_timing.py` (new) into
`data/timing/<x>.json` (every spell, missile and basic attack of the 14 champions). Cross-checked against the League wiki
(cast time / speed / delay of every ability of all 14 champions, plus infobox windup and missile speed).

1. **`missileSpeed` in SpellDataResource is a stale legacy field.** The real speed is `mMissileSpec.movementComponent`
   (`FixedSpeedMovement.mSpeed`, `AcceleratingMovement.mInitialSpeed / mAcceleration / mMinSpeed / mMaxSpeed`,
   `FixedTimeMovement.mTravelTime`). Examples: Ezreal W legacy 1200, real 1700; Lux E 1300 vs 1200; Veigar / Annie basic
   attacks 1100 / 1200 vs 1500 (wiki: 1500). `data/champions/*_game.json` and `data/anim/*.json` still carry the legacy value
   (used for bot aim only); the kits now read `data/timing` (`ChampionKit.missile_speed_of`).
2. **Effective cast time** = `mCastTime` if present, else `spellCastTime`, else `castFrame / 30` (animation frame at 30 fps).
   Verified on every roster ability: Ezreal R 1.0, Jinx R 0.6 (mCastTime, not the 0.25 spellCastTime), Darius R 0.3667,
   Malphite E 0.2419, Garen R 0.435, Yasuo W 0.013, MF R 0.001. Where the wiki says "none" (toggles, buffs, empowered
   attacks, Yi, Garen, Sona, Malphite W / R, Leona Q / W ...) the spell is instant; the stale `spellCastTime` there is not used.
3. **Basic attack windup** = `0.3 + mAttackDelayCastOffsetPercent` of the attack period (or `mAttackCastTime / mAttackTotalTime`
   for Jinx), blended with the windup modifier (`...AttackSpeedRatio`) as in `Unit.attack_windup`. Verified in engine for all 14.
4. Movement during a windup: every main-slot spell has `mCantCancelWhileWindingUp` true; ours stops the champion, buffers
   the move order and walks on when the cast ends (measured: 0.05 m of drift = one frame). Same as League.

## Fixes (spell | field | ours | League | source | fixed)

| Spell | Field | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|---|
| Jinx W Zap! | missile speed | 3300 | 3300 (FixedSpeed) | JinxWMissile mMissileSpec, wiki | already right (measured 3300 in engine) |
| Jinx W Zap! | cast time | 0.6 - 0.08 x bonus AS, min 0.4 | same (mCastTime 0.6, `JinxLowEndWCastTime` 0.4, `JinxWASpeedCastTimeScalarPerHundrethSecond` 0.08) | JinxWMissile / JinxW data values, wiki "0.6 - 0.4" | already right |
| Jinx Q rockets | attack missile speed | 2750 (minigun value) | 2000 | JinxQAttack / JinxQCritAttack mMissileSpec | yes |
| Jinx R | speed | 1700, 2200 after 1350 u | same | JinxR mMissileSpec + wiki | already right |
| Annie basic attack | missile speed | 1200 | 1500 | AnnieBasicAttack mMissileSpec, wiki infobox | yes |
| Veigar basic attack | missile speed | 1100 | 1500 | VeigarBasicAttack mMissileSpec, wiki infobox | yes |
| Veigar R | missile | flat 1100 | accelerating 500 u/s, +4000 u/s^2, min 500, max 4000 | VeigarR AcceleratingMovement | yes (`K.homing_missile` accel / min / max) |
| Veigar W | impact delay | 1.2 s after the windup (1.45 s from press) | 1.221 s from the start of the cast | wiki ("1.221 seconds delay ... starts at the beginning of the cast time"), data ImpactDelay 1.2 | yes |
| Lux W out | missile | flat 2200 | 2200 decelerating 2300 u/s^2 to min 500 | LuxPrismaticWaveMissile | yes (flight ~1.1 s instead of 0.5 s) |
| Lux W return | missile | 1400, +1500 u/s^2 | 50 u/s, +1800 u/s^2, max 2400 | LuxPrismaticWaveReturn | yes |
| Lux E | missile speed | 1300 | 1200 | LuxLightStrikeKugel FixedSpeed (legacy 1300) | yes |
| Ahri passive | essence orb | flat 1400 | 1800 +800 u/s^2, min 1200, max 8000 | AhriPassiveMissile | yes |
| Ahri R | dash speed | flat 1200 | 1200 + 100% move speed | wiki, RBaseDashSpeed 1200 | yes |
| Ahri W Fox-Fire | orbit speed | 1 turn / 1.2 s | 2.65 rad/s (1 turn / 2.37 s); wiki prints 75.92 deg/s (half) | AhriWMissile CircleMovement mAngularVelocity | yes (bin value; the wiki figure would be 4.7 s per turn: unresolved) |
| Annie W Incinerate | damage timing | per-target delay distance / 2800 u/s (<= 0.2 s) | whole cone at cast end: no missile / delay in the bin | AnnieW SpellData, wiki "0.25" | yes |
| Yasuo Q | cast time | 0.35 / (1 + bonus AS), floor 0.175 (also for the whirlwind) | thrust 0.35 -> 0.175, whirlwind 0.35 -> 0.28 | wiki end points | yes (linear to the cooldown-floor AS, 111.3%; the in-between curve is inferred) |
| Master Yi Q | untargetable total | 4 x 0.231 + 0.08 | 4 x 0.231 + 0.165 (1.087 s with 4 marks) | wiki | yes |
| Miss Fortune R | wave timing | first wave at 0 s, every 3 s / waves (0.214 / 0.1875 / 0.167) | first wave 0.066 s, then 0.2036 / 0.1781 / 0.1583 s per rank | wiki | yes |
| Malphite E | cast time | 0.24 | 0.2419 | Landslide mCastTime | yes |
| Fountain turret | windup | 13.9% (lane turret value) | 40% (castOffset +0.1) | HA_AP_OrderShrineTurret | yes |

## Verified identical (no change)

| Item | Ours = League | Source |
|---|---|---|
| Ezreal Q / W / E / R | cast 0.25 / 0.25 / 0.25 / 1.0; missile 2000 / 1700 / 2000 / 2000 | EzrealQ.. mMissileSpec, wiki |
| Ahri Q out / back | 2500 -3200 u/s^2 min 400; 60 +1900 max 2600 | AhriQMissile / ReturnMissile |
| Ahri E, R bolts, W flames | 1550, 1400, 1400; cast 0.25, none, none | bins, wiki |
| Annie Q | homing 1400, cast 0.25 | Disintegrate |
| Leona E | blade 2000, cast 0.25; R delay 0.625, cast 0.25 | wiki |
| Malphite Q / R | 1200 (min = max = init); R dash 1500 + 100% MS | wiki |
| MF Q / R bullets | 1400, dud 400; 2000 | bins |
| Sona Q / W / E / R | homing 1300; Crescendo 2400, cast 0.25 | bins |
| Yasuo E dash | 750 + 60% MS; Q3 tornado 1200; W cast 0.013 | wiki, bins |
| Darius | Q windup 0.75, E cast 0.25, R cast 0.3667 | wiki |
| Basic attack missile speeds | Ahri 1750, Ezreal 2000, Jinx 2750, Lux 1600, MF 2000, Sona 1500 | CharacterRecord / attack spells |
| Basic attack windups | all 14 within 0.035 s of the League formula (measured in engine) | `timing_test.gd` |
| Minions | windup 0.491 / 0.313 / 0.3 / 0.347 of the attack time, ranged missile 650, siege 1200 | HA_*Minion* records |
| Lane turrets | windup 13.9%, missile 1200, AS 0.833 | TurretBasicAttack, HA_* |
| Summoners | Flash / Heal / Barrier / Cleanse / Ghost / Clarity instant; Mark 1200 (width 50), dash 2500 | SummonerSnowball etc. |

## Open (not fixed)

| Item | Why |
|---|---|
| Darius E: 0.4 s no-move / no-cast lockout after the cast, R: 0.25 s | wiki only; needs a lock that `Unit.casting` cannot express without re-running `execute` |
| Leona E dash speed (ours max(22 m/s, d / 0.3)), Garen R sword delay 0.18 s, Darius E pull 0.28 s | no value in the bins or the wiki |
| Yi Q: per-bounce travel (0.2 / 0.18 / 0.15 s FixedTime in the bins) vs the wiki 0.231 s mark interval | wiki interval kept |
| "casts from where the caster is at the START of the cast time" (Jinx W, Lux W, Sona R) | we cast from the position at the end of the windup (she cannot move during it, so only forced displacement differs) |
| Ahri W: 0.25 s / 0.4 s targeting delays (data InitialDelay / SecondaryDelay) | semantics unknown (kit uses 0.25 + 0.12 stagger) |
| Static `data/champions/*_game.json` `missileSpeed` still legacy | only bot aim read it; replaced by `data/timing` |
| A black blob with a blue ring at the top right of the Ezreal Q fog screenshots | a static map particle (not the Q); the subtractive-in-fog fix does not cover it, owner: VFX / env |

## Jinx W (the player's report)

Measured in engine at level 18: cast 0.518 s (0.6 - 0.08 x 0.82 bonus AS), missile spawned at the end of the windup at
exactly 3300 u/s (5 m in 0.14 s; 1500 u range in 0.45 s), identical to JinxWMissile and the wiki. No data discrepancy was
found, so the "too fast" impression is not a speed constant. Likely contributors: Zap! is fired at the end of a 0.52 s
windup whose animation is clamped to 0.75x (the gun recoil plays ~0.2 s before the bolt leaves), and the VFX bolt. If the
player still sees it wrong, the next thing to check is the cast animation playback rate against the missile launch.

## Check harness

- `tools/lol/extract_timing.py` regenerates `data/timing/*.json`.
- `src/debug/timing_test.gd` (headless): per champion measures the basic attack windup and missile speed, then casts Q W E R
  at a dummy and measures cast time, movement lock, dash time and missile speed / acceleration / floor, against the bins and
  the EXPECT table (wiki cast times, with sources). Run `tools/timing_check.sh [Champ ...]`; prints `TIMING PASS|FAIL`.
- Result: all 14 champions 0 failures (`TIMING DONE <champ> passes=N fails=0`).
- Screenshots: `src/debug/timing_fog_shot.gd` (Ezreal Q over fogged ground, shots `timing_fog/A_*.png`, `B_*.png`).
