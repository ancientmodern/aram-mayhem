class_name Rules
extends RefCounted
## Game-mode constants for ARAM: Mayhem (patch 26.20 values, see docs/research).

const START_LEVEL := 3
const START_GOLD := 1400.0
## Classic ARAM (wiki ARAM page): Mayhem-only values are kept behind MAYHEM_MODE for reference.
const MAYHEM_MODE := false
const PASSIVE_GOLD_PER_SEC := 8.5 if MAYHEM_MODE else 6.0   ## Mayhem 42.5 / 5 s; classic ARAM 60 / 10 s
const PASSIVE_GOLD_START := 60.0
const PASSIVE_XP_PER_SEC := 5.0
const MAX_LEVEL := 18
## XP needed to go from level i to i+1 (Howling Abyss curve; levels 1-2 unused in ARAM).
const XP_TO_NEXT := [0, 280, 380, 478, 510, 750, 780, 880, 980, 1080, 1180, 1280, 1380, 1480, 1580, 1680, 1780, 1880]
const RESPAWN := [0, 9, 10, 11, 13, 15, 17, 19, 21, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40]
const KILL_XP := [0, 35, 95, 155, 215, 275, 335, 395, 455, 515, 590, 640, 690, 740, 790, 840, 890, 940, 990]
const KILL_GOLD := 200.0
const FIRST_BLOOD_GOLD := 90.0
const ASSIST_GOLD_POOL := 90.0
## Mayhem augments are off: the game focuses on classic ARAM (code kept, not run).
const AUGMENTS_ENABLED := false
const AUGMENT_LEVELS := [3, 7, 11, 15]
const AUGMENT_CHOICES := 3
## Tier weights per augment screen index [silver, gold, prismatic]
const TIER_WEIGHTS := [[0.15, 0.55, 0.30], [0.30, 0.45, 0.25], [0.30, 0.40, 0.30], [0.25, 0.40, 0.35]]
const GOLDEN_REROLL_CHANCE := 0.2
const FIRST_WAVE_TIME := 40.0 if MAYHEM_MODE else 50.0   ## classic ARAM: minions from 0:50
const WAVE_INTERVAL := 25.0
## ARAM: 25 s waves early, tightening to 13 s late by game minute (exact curve not published; linear 10:00 -> 22:00).
const WAVE_INTERVAL_LATE := 13.0
const WAVE_SPAWN_GAP := 0.8
const MINION_UPGRADE_INTERVAL := 45.0
const MINION_MS_START := 360.0             ## +10 MS every 60 s after this
const RELIC_OUTER_FIRST := 105.0
const RELIC_INNER_FIRST := 150.0
const RELIC_RESPAWN := 90.0
const RELIC_PICKUP_HEAL := 0.08
const RELIC_BEAM_HEAL := 0.22
const RELIC_BEAM_RADIUS := 850.0
const RELIC_BEAM_DELAY := 2.5
const INHIBITOR_RESPAWN := 300.0
const SHOP_RADIUS := 14.0                  ## meters from the spawn point (platform)
const AS_CAP := 5.0
const CRIT_DAMAGE := 2.0
const SUMMONER_HASTE := 70.0               ## Howling Abyss aura
const ARAM_OUTGOING_HEAL := 0.5            ## ARAM: healing on other units -50%
const BASE_GATE_TIME := 15.0
const LONG_RANGE_DR_START := 1000.0
const LONG_RANGE_DR_END := 2000.0


static func xp_to_next(level: int) -> float:
	if level >= MAX_LEVEL:
		return INF
	return XP_TO_NEXT[level]


## Respawn time (seconds) for a champion level and game time (seconds).
static func respawn_time(level: int, game_time: float) -> float:
	var base: float = RESPAWN[clampi(level, 1, MAX_LEVEL)]
	if game_time > 1440.0:
		base *= 1.0 + minf(0.25, (game_time - 1440.0) / 60.0 * 0.025)
	return base


static func kill_xp(victim_level: int) -> float:
	return KILL_XP[clampi(victim_level, 1, MAX_LEVEL)]


## Mayhem base HP bonus by level (melee +20->600, ranged +20->400).
static func mayhem_hp_bonus(level: int, melee: bool) -> float:
	var top := 600.0 if melee else 400.0
	return 20.0 + (top - 20.0) / 17.0 * (level - 1)


## Damage multiplier for champion-vs-champion damage at long range (ARAM rule).
static func long_range_mult(dist_units: float) -> float:
	if dist_units <= LONG_RANGE_DR_START:
		return 1.0
	var k := clampf((dist_units - LONG_RANGE_DR_START) / (LONG_RANGE_DR_END - LONG_RANGE_DR_START), 0.0, 1.0)
	return lerpf(0.85, 0.70, k)
