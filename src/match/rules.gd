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
const MINION_UPGRADE_INTERVAL := 49.99     ## [numbers] BarracksConfig UpgradeIntervalSecs (was 45)
## [numbers] BarracksConfig MoveSpeedIncrease*: +25 MS every 300 s from 600 s, 4 times (325 -> 425; was +10 / 60 s from 360 s)
const MINION_MS_START := 600.0
const MINION_MS_INTERVAL := 300.0
const MINION_MS_STEP := 25.0
const MINION_MS_STEPS := 4
const RELIC_OUTER_FIRST := 105.0
const RELIC_INNER_FIRST := 150.0
const RELIC_RESPAWN := 90.0
const RELIC_PICKUP_HEAL := 0.08
const RELIC_BEAM_HEAL := 0.22 if MAYHEM_MODE else 0.16   ## League data: 16% missing health (Mayhem 22%)
const RELIC_BEAM_RADIUS := 850.0
const RELIC_BEAM_DELAY := 2.5
const INHIBITOR_RESPAWN := 300.0
const SHOP_RADIUS := 14.0                  ## meters from the spawn point (platform)
## [numbers] League gcd_AttackMinDelay: 0.333 s in classic ARAM (Map12 ARAM GameModeConstants) = 3.003 attacks/s; the
## Mayhem ("Kiwi") constants set 0.2 s = 5.0. (Was 5.0 for both.)
const AS_CAP := 5.0 if MAYHEM_MODE else 3.003
const CRIT_DAMAGE := 2.0                   ## base crit multiplier (200%; wiki Critical strike, V26.01; CharacterRecord critDamageMultiplier 2.0)
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
## [numbers] League DeathTimes (Map12 ARAM mDeathTimes): the per-level table above, scaled after mScalingStartTime
## (1440 s) by +2.5% for every started mScalingIncrementTime (60 s), capped at x1.25. League steps this (the wiki's
## SR formula uses ceil too); it used to be a smooth ramp.
const DEATH_SCALE_START := 1440.0
const DEATH_SCALE_STEP := 60.0
const DEATH_SCALE_PER_STEP := 0.025
const DEATH_SCALE_CAP := 0.25
static func respawn_time(level: int, game_time: float) -> float:
	var base: float = RESPAWN[clampi(level, 1, MAX_LEVEL)]
	if game_time > DEATH_SCALE_START:
		var steps := ceilf((game_time - DEATH_SCALE_START) / DEATH_SCALE_STEP)
		base *= 1.0 + minf(DEATH_SCALE_CAP, steps * DEATH_SCALE_PER_STEP)
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


# ===================================================================== [numbers] ARAM economy / XP / structure rules
## Everything below is League's Map12 ARAM data (map12.bin: ARAM GameModeConstants 332b9e84, ExperienceCurveData
## d88e5d96, ExperienceModData 45163f15, kill-bounty config 67d58a41, HA BarracksConfig) unless a comment says "wiki".
## Damage ratios (dr_UnitToHero / dr_UnitToBuilding): lane-minion damage to champions and to structures is halved.
const UNIT_TO_HERO_DR := 0.5
const UNIT_TO_BUILDING_DR := 0.5
## Wiki (ARAM, Howling Abyss aura): area damage deals 75% to minions.
const AOE_VS_MINION := 0.75
## Wiki (ARAM, "Late-game bonus damage to structures"): champion damage to structures +0% -> +25% from 18:00 to 30:00;
## melee champions with more AP than AD get a flat +20% instead if that is higher.
const STRUCT_BONUS_START := 1080.0
const STRUCT_BONUS_END := 1800.0
const STRUCT_BONUS_MAX := 0.25
const MELEE_AP_STRUCT_BONUS := 0.2
## Wiki (Turret / Basic attack): champion basic attacks vs structures deal base AD + bonus AD + 60% AP.
const STRUCT_AP_RATIO := 0.6
## Turret items (Global Items/1500 "Penetrating Bullets"): +30% armor penetration. (No melee weakness / reinforced armor in
## Howling Abyss: those are the Summoner's Rift "Reinforced Armor" items.)
const TURRET_ARMOR_PEN := 0.3
## Per-champion share of lane-minion XP by number of enemy champions in range (ExperienceModData mPlayerMinionSplitXp).
const MINION_XP_SPLIT := [0.92, 0.6, 0.4, 0.3, 0.24]
const MINION_XP_RANGE := 14.0              ## BarracksConfig ExpRadius 1400
const MINION_GOLD_RANGE := 12.5            ## BarracksConfig goldRadius 1250 (HA aura: 6 gold for nearby minion deaths)
const MINION_NEARBY_GOLD := 6.0            ## wiki ARAM: "6 gold when a nearby minion dies within 1250 units"
const KILL_XP_RANGE := 16.0                ## wiki Experience: champion kill XP within 1600 units
## Champion-kill XP comeback: +16% (ARAM LevelDifferenceExperienceMultiplierPerLevel) per level the victim is above the
## killer (and minus per level below, floored at 40% of base like the wiki's SR rule).
const KILL_XP_LEVEL_DIFF := 0.16
const KILL_XP_MIN_MULT := 0.4
## Victim level -> multiplier on the kill XP when the kill is shared (mExperienceGrantedMultForSharedKillPerLevel).
const SHARED_KILL_XP_MULT := [0.666, 0.666, 0.666, 0.666, 0.666, 0.666, 0.82, 0.82, 0.9]
## Kill bounty (67d58a41): BaseGold 200 flat, +90 first blood, +90 assist pool, bounty accrues 1 per 2 gold earned from
## kills/assists up to +600 and loses 1 per 4 gold paid out on death; early-game bounties ramp 50% -> 100% 1:30 -> 3:30.
const BOUNTY_ACCRUAL := 0.5
const BOUNTY_DEPRECIATION := 0.25
const BOUNTY_MAX_BONUS := 600.0
const BOUNTY_EARLY_START := 90.0
const BOUNTY_EARLY_END := 210.0
const BOUNTY_EARLY_MIN := 0.5
## Structures (Turret HA_* records + wiki): global rewards and the 250 HP per enemy champion rule.
const TURRET_GLOBAL_GOLD := 150.0
const TURRET_GLOBAL_XP := [30.0, 70.0, 120.0, 0.0]    ## outer, inhibitor turret, nexus turret, fountain
const INHIBITOR_LAST_HIT_GOLD := 50.0      ## wiki Inhibitor: 50 gold to the champion with the last hit only
const TURRET_HP_PER_ENEMY_CHAMP := 250.0
## Wiki Inhibitor (Howling Abyss): super minions for the next 10 waves = until the final two waves before it respawns.
const SUPER_STOP_WAVES_BEFORE_RESPAWN := 2


## Champion kill XP for the killer (solo) or each participant (shared), League ARAM rules.
static func champion_kill_xp(victim_level: int, killer_level: int, participants: int) -> float:
	var base := kill_xp(victim_level)
	var diff := victim_level - killer_level
	var mult := 1.0
	if diff > 0:
		mult += KILL_XP_LEVEL_DIFF * diff
	elif diff < 0:
		mult = maxf(KILL_XP_MIN_MULT, 1.0 + KILL_XP_LEVEL_DIFF * diff)
	var xp := base * mult
	if participants > 1:
		xp *= SHARED_KILL_XP_MULT[mini(maxi(victim_level, 1), SHARED_KILL_XP_MULT.size()) - 1] / participants
	return xp


## XP each champion gets from a lane-minion kill when `n` enemy champions share it.
static func minion_xp_share(base_xp: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return base_xp * MINION_XP_SPLIT[mini(n, MINION_XP_SPLIT.size()) - 1]


## Early-game kill/assist bounty scale (50% -> 100%).
static func early_bounty_scale(game_time: float) -> float:
	return lerpf(BOUNTY_EARLY_MIN, 1.0, clampf((game_time - BOUNTY_EARLY_START) / (BOUNTY_EARLY_END - BOUNTY_EARLY_START), 0.0, 1.0))


## ARAM late-game structure damage bonus (+0% at 18:00 -> +25% at 30:00).
static func structure_bonus(game_time: float) -> float:
	return STRUCT_BONUS_MAX * clampf((game_time - STRUCT_BONUS_START) / (STRUCT_BONUS_END - STRUCT_BONUS_START), 0.0, 1.0)
