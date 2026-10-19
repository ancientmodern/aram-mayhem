# Numbers audit (classic ARAM, Howling Abyss, patch 26.20 / client 16.20)

Owner: [numbers] agent, 2026-10-18. Player report: "attacking turrets only uses attack damage; League compensates based on AP.
Audit ALL numeric problems."

**Method.** Data first: the installed game files (`D:\Riot Games\League of Legends\Game`, client 16.20.8248524), read with
`tools/lol/numbers_dump.py` (resolves WAD paths and bin names with the CommunityDragon hash lists in `tools/extracted/cdhash`)
plus the in-game string table (`data/menu/en_us/lol.stringtable`, buff / item tooltips). The wiki (WebFetch only; the wiki
blocks curl) second, for rules the engine implements in compiled code (the Lua scripts in `Scripts.wad` are empty stubs, so
turret damage ramp, ARAM damage modifiers etc. are not in data).

Key data sources (all in `Maps/Shipping/Map12.wad.client` unless noted):

| Source | Path / entry | Holds |
|---|---|---|
| Map bin | `data/maps/shipping/map12/map12.bin` | ARAM `GameModeConstants` (332b9e84), `ExperienceCurveData` (d88e5d96), `ExperienceModData`, `DeathTimes` (a40f595b), kill-bounty config (67d58a41), `BarracksConfig`, `GameplayConfig` (lethality, adaptive scales, ability haste max), relic aura spell |
| Structures | `data/characters/turret/turret.bin` (HA_Outer, HA_Inhibitor, HA_Nexus), `inhibitor.bin`, `nexus.bin`, `ha_ap_ordershrineturret.bin` | HP, armor, AD, AS, range, global gold / XP |
| Minions | `data/characters/ha_<team>minion{melee,ranged,siege,super}.bin` | HP, AD, AS, range, XP, gold |
| Turret items | `Global.wad.client` `Items/1500..1524` (hash `1d720f4f42640c18`) | Penetrating Bullets (30% armor pen, warming up 50% x3 / 5 s), Fortification (35%, 60 s), **Tower Power-Up** (the Howling Abyss turret ramp), Overcharged HA |
| Summoner spells | `Global.wad.client` `Shared/Spells/Summoner*` (hash `5a791d818ae738a6`) | cooldowns, heal / barrier / ignite / ghost calculations |
| Strings | `Localized/Global.en_US.wad.client` | Howling Abyss aura text (+70 haste, allied heals x0.5, AoE vs minions x0.75, 6 gold for nearby minion deaths) |

Harness: `src/debug/numbers_test.gd` (headless, 100+ assertions): `godot --headless --path . --fixed-fps 60 -- --champ=Ezreal --harness=res://src/debug/numbers_test.gd`
(use a champion without ARAM modifiers; Ezreal has none). Prints `NUM PASS|FAIL`, then `NUM DONE passes=N fails=N`.

## 1. Champion attacks vs structures, turrets, inhibitors, nexus

| Item | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Basic attack vs structure | AD only, always physical, crit applied | base AD + bonus AD + **60% AP**; the whole hit is physical if bonus AD >= 60% AP, otherwise magic; basic attacks cannot critically strike structures | wiki Turret, Basic attack, Nexus, Critical strike | yes (`Unit.attack_hit`) |
| Melee +20% vs turrets | on all turrets | Not a Howling Abyss turret property (that is the SR "Reinforced Armor" / Turret Plating item). The HA aura: melee champions with more AP than AD deal +20% to structures until the time bonus passes it | wiki ARAM, Items 1502/1515 | yes (`Combat._aram_damage_ratio`) |
| Late-game structure damage | none | champion damage to structures +0% -> +25% from 18:00 to 30:00 | wiki ARAM | yes (`Rules.structure_bonus`) |
| Lane minion damage to champions / structures | 100% | x0.5 / x0.5 (`dr_UnitToHero`, `dr_UnitToBuilding` in the ARAM constants) | map12.bin 332b9e84 | yes |
| Spells vs structures | excluded (ability targeting) | structures are hit by basic attacks only (a few special cases) | wiki Basic attack | already right |
| Outer turret HP | 2550 | 1300 + 250 per enemy champion (= 2550) | HA_Outer + wiki | ok |
| Inhibitor turret HP | 5150 | 3900 + 1250 | HA_Inhibitor + wiki | ok |
| Nexus turret HP | 3000 (Mayhem value) | 1800 + 1250 = 3050 | HA_Nexus + wiki | yes |
| Turret AD | 185 + 6/min (outer), 205/195 + 9/min, capped at 15 min (275/340/330) | 185 / 205 / 195 base; Tower Power-Up: +9/min until 12:00 (outer, ends 293) and +12/min until 15:00 (inhibitor 385, nexus 375) | Items/1522 (effects 9 / 12, `BonusStatsFalloffTime` 720, `InhibNexusDamageAmpEndTime` 900), wiki ranges 185-293 / 205-385 / 195-375 | yes |
| Turret armor / MR | constant 60 / 63 / 60 | +3/min until 8:10 (`StatAddEndTime` 490, +21 -> 81 / 84 / 81); the outer turret's resists drop to 40 at 12:00 | Items/1522, wiki (60-81, 63-84, "reduced to 40 at 12:00") | yes |
| Turret armor penetration | none | 30% (Penetrating Bullets) | Items/1500 | yes |
| Warming Up | +50% per hit up to +150%, reset after 5 s | same | Items/1500 | ok |
| Turret missile speed / windup | 1300 / 15% | 1200 / 13.9% (`mAttackDelayCastOffsetPercent` -0.161) | TurretBasicAttack | yes |
| Fountain turret | AS 3.0, range 1100, true damage | AS 2.5, range 1100, AD 999 | ha_ap_ordershrineturret.bin | AS fixed |
| Turret damage to minions | melee 45%, caster 70%, siege 14%, super 7% of max HP | super 5% (wiki Turret V6.22 values; melee 45% since V8.5); the per-shot percentages ignore armor | wiki | super + armor fixed |
| Targeting priority | pets, siege/super, melee, caster, champions; switch to a champion hitting an ally | same order; switch to a champion that damages an allied champion within 1400 | wiki Turret | ok |
| "No minions nearby" -80% damage (Reinforced Armor) | on every turret | not a Howling Abyss turret feature (item text: "lane minions or Rift Herald"; HA turret items are 1500, 1521, 1522, 1520) | Items/1502, wiki HA turret feature list | removed |
| Inhibitor turret Fortification | 40% for 70 s (Mayhem) | 35% for 60 s after the outer turret falls | Items/1521 (effect 0.35, `FortificationTimer` 60), wiki | yes |
| Inhibitor / nexus turret regeneration | none | 3 HP/s (segments 30/75/100%) and 6 HP/s (40/70/100%) | wiki Turret | yes |
| Overcharged HA (35:00 resist loss, 40:00 HP loss) | none | Items/1520 | Items/1520 | **not done** (games past 35:00 only) |
| Inhibitor HP / regen / armor / MR | 4000 / 15 / 20 / 20 | 4000 / 15 per s / 20 / 0; penetration has no effect on an inhibitor | inhibitor.bin, wiki Inhibitor | MR + pen fixed |
| Nexus HP / regen / armor / MR | 3000 / 10 / 20 / 20 | 5500 (Mayhem -2500) / 20 per s / 20 / 0 | nexus.bin, wiki Nexus | yes |
| Inhibitor respawn | 300 s | 5 min | wiki | ok |
| Turret gold / XP | 150 gold team-wide, no XP | `globalGoldGivenOnDeath` 150; `globalExpGivenOnDeath` 30 (outer) / 70 (inhibitor) / 120 (nexus turret) to the team | HA_* records | XP added |
| Inhibitor gold | 50 to the whole team | 50 to the last-hitting champion only | wiki Inhibitor | yes |
| Super minions | 1 per wave while the inhibitor is down | 1 per wave, but not for the final two waves before it respawns (wiki "next 10 waves") | BarracksConfig `SpawnCountPerInhibitorDown`, wiki | yes |

## 2. Damage formulas and stats

| Item | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Armor / MR reduction | 100/(100+r); negative: 2 - 100/(100-r) | same | wiki Armor | ok (tested) |
| Penetration order | percent, then lethality, both ignored at <= 0 | flat reduction, percent reduction, percent pen, bonus percent pen, lethality | wiki Armor penetration | ok |
| Lethality level scaling | none | none since V14.1 (`mLethalityPercentGivenAtLevel0` 1.0) | GameplayConfig | ok |
| Base crit damage | 200% | 200% (V26.01); `critDamageMultiplier` 2.0 | wiki, CharacterRecords | ok |
| Crit chance above 100% | converted to adaptive force (Mayhem rule) | wasted in classic ARAM | wiki Critical strike | yes (Mayhem-only now) |
| Attack speed cap | 5.0 | 3.003 (`gcd_AttackMinDelay` 0.333); Mayhem 5.0 | ARAM GameModeConstants | yes |
| Attack speed formula | base + ratio * bonus | same; growth is bonus AS | wiki Attack speed | ok |
| Total attack speed multipliers (ARAM Yasuo +2.5%, Jinx passive) | folded into bonus AS (wrong with items) | multiplier on total AS | wiki | yes (`as_total%`) |
| Level scaling | g*(n-1)*(0.7025+0.0175*(n-1)) | same | wiki Champion statistic | ok (tested) |
| Movement speed soft caps | 415 / 490 / 220, slows before caps | same, slows applied last | wiki Movement speed | ok |
| Ability haste -> cooldown | 100/(100+AH) | same, max 500 | `AbilityHasteMax` | cap added |
| Summoner haste | 100/(100+haste), +70 aura | same | wiki Ability haste | ok |
| Tenacity | additive sum, cap 90%, nearsight reduced, slows not | multiplicative inside a group (items; Cleanse / mode; Garen / debuffs), groups add, cap 100%, min 0.3 s; airborne / suppression / stasis / nearsight ignore it; slows are affected | wiki Tenacity | yes |
| Life steal / omnivamp / spell vamp | all full, x0.33 for pets | omnivamp and spell vamp x0.333 for AoE / pet / DoT and vs minions; life steal x0.33 for AoE / pet; aura: life steal and omnivamp -40% vs minions | map12.bin constants, wiki ARAM | yes (`Combat.vamp_fraction`) |
| Ally heals | x0.5 (not self, relics, vamp) | same | aura text | ok |
| Grievous wounds | heals only | heals, incoming healing and health regeneration | wiki Ignite | regen added |
| Area damage vs minions | 100% | 75% | aura text | yes |
| Melee champions | +15 armor and MR only in Mayhem | +15 bonus MR, +20% vs siege and super minions | wiki ARAM | yes |
| Mana regeneration aura | Mayhem only | +0.1% max mana per second | wiki ARAM | yes |
| Per-champion ARAM modifiers (14 champions) | present | verified against the wiki ARAM page | wiki ARAM | ok |
| Long-range champion damage | 85% -> 70% from 1000 to 2000 | same | wiki ARAM | ok |

## 3. Economy and progression

| Item | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Starting gold / passive gold | 1400 / 6 g/s from 1:00 | 1400 / 30 per 5 s from 1:00 | ARAM constants | ok |
| Passive XP | 5/s | 5/s | ARAM constants | ok |
| XP curve, kill XP table, level 3 start | table | identical | ExperienceCurveData d88e5d96 | ok |
| Kill gold | 300 + 100 per streak kill, +100 first blood | 200 flat + accrued bounty (+0.5 per gold earned from kills / assists, max +600, -0.25 per gold paid out), x0.5 -> x1.0 between 1:30 and 3:30, +90 first blood | kill-bounty config 67d58a41 | yes |
| Assist gold | (0.5 * bounty + 50) / N | (0.5 * bounty + 90 pool) / N; assist window 20 s | config 67d58a41 | yes |
| Kill XP | killer full, assisters 50% each | solo full; shared: victim-level multiplier (0.666 / 0.82 / 0.9) split equally; +16% per level the victim is above | ExperienceCurveData, ExperienceModData | yes |
| Minion XP split | 1 / 1 / 1.3 / 1.35 / 1.4 / 1.45 per N, range 16 m | per champion 0.92 / 0.6 / 0.4 / 0.3 / 0.24, range 14 m | ExperienceModData, BarracksConfig `ExpRadius` 1400 | yes |
| Nearby minion death gold | none | 6 gold to other enemy champions within 12.5 m | aura text, `goldRadius` 1250 | yes |
| Respawn timer | smooth +2.5%/min after 24:00 | stepped +2.5% per started minute, cap +25% | DeathTimes a40f595b | yes |
| Minion upgrade interval | 45 s | 49.99 s | BarracksConfig | yes |
| Minion HP growth / upgrade | melee 27, caster 9, siege 34, super 150 | 19.8 / 6.6 / 25.3 / 100, after 6 upgrades 6.75 / 2.25 / 25 / 100 | BarracksConfig | yes |
| Super minion | 1600 HP, 230 AD | 1500 HP, 10 regen/s, 306 AD, 60 armor, 10 MR, 100 XP, 45 gold | ha_*minionsuper.bin | yes |
| Minion gold | 21 / 17 / 52 (+0.5 per upgrade) | 20 / 17 / 44 (+0.125 melee, +0.35 siege and super per upgrade) | records, BarracksConfig | yes |
| Minion move speed | +10 per 60 s from 6:00 | +25 every 300 s from 10:00, four times (325 -> 425) | BarracksConfig, wiki | yes |
| Minion windups | 0.4 / 0.35 / 0.3 / 0.3 | 0.491 / 0.313 / 0.3 / 0.347 (cast time / total time) | records | yes |
| Siege minion cadence | every 3rd wave, then every 2nd from 10:45, then every wave from 25:00 | same | BarracksConfig | ok |
| Relic heals | pickup 8%, beam 16% HP / 8% mana, allies only | beam 16% HP and mana to every champion in 850 u (enemies included); pickup 8%; delay 2.5 s; respawn 90 s | relic aura data, wiki Health Relic | beam mana + enemies fixed |

## 4. Summoner spells (ARAM set)

| Item | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Heal | 90 + 15/level (345), MS 2 s, range 850, no repeat penalty | 80 -> 318 by level, +30% MS for 1 s, range 900, 50% less when healed in the last 30 s | SummonerHeal | yes |
| Barrier | 105 + 18/level (411) | 100 -> 460 | SummonerBarrier | yes |
| Cleanse | 65% tenacity | 75% for 3 s (group B) | SummonerBoost | yes |
| Ignite | 70 + 20/level (410) | 70 -> 475 (+20 per level to 5, +25 from 6) | SummonerDot | yes |
| Ghost 24-48% MS | ok | ok | SummonerHaste | ok |
| Clarity 50% / 25% ally | ok | ok | SummonerMana | ok |
| Flash 400 u, cooldowns (300 / 240 / 240 / 180 / 180 / 240 / 80) | ok | ok | records, wiki Summoner spell | ok |
| Mark | snowball speed 1300 / radius 60, Dash 1800 u/s, no damage on arrival, no cooldown refund | 1200 / width 50, Dash 2500 u/s, Dash deals the same 15-100 true damage on arrival, a successful Dash cuts Mark's remaining cooldown by 25% | SummonerSnowball, wiki Mark | yes |
| Exhaust | not in the game | available in ARAM: 290 s, range 650, 3 s, 40% slow, target deals 35% less (not true) damage | wiki Exhaust | yes (added, no VFX: no extracted particle) |

## 5. Champion abilities and items

### 5a. Champion abilities (14 champions, every rank checked against `data/champions/*_game.json`, the champion bins and the wiki)

Per-rank damage, ratios, costs, cooldowns and the ARAM overrides (Lux R 80/70/60, Sona Hymn 10 s / Aria 13 s / Accelerando cap 30,
Veigar Event Horizon 23-17 s and 3 stacks per takedown, Yasuo Wind Wall 27-19 s, Garen Courage 0.4, the `mayhem_aura.gd`
dealt / taken / heal / shield / total-AS table) were checked for all five slots of all 14 champions. Discrepancies found:

| Champion / ability | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Annie E cooldown | 14/13/12/11/10 | 10 at every rank | wiki Annie V26.04 | yes |
| Annie Tibbers enrage AS | 0.625 x 3.75 decaying with time | per attack 1.736/1.536/1.307/1.043/0.739, then 0.625 | wiki Annie | yes |
| Annie Q target dies in flight | no refund | mana and 50% cooldown refunded | wiki Annie | yes |
| Annie W cone | 50 deg | 49.52 deg (data holds the half angle) | annie_game.json | yes |
| Garen passive regen | linear 1.5% -> 10.1% | stepped (L6 2.5%, L9 4.9%, L18 10.1%), reduced by Grievous Wounds | garen.bin | yes |
| Leona passive | 24 + 8/level | 25 + 7/level (32 ... 151) | leona.bin | yes |
| Leona Q / Darius W empowered attack | no extra reach | +50 / +25 range | wiki | yes |
| Jinx Q Rev'd up stacks | max/3 each | first stack max/2, then max/4 each | wiki Jinx | yes |
| Jinx passive attack speed | +25% bonus AS per stack | +25% **total** AS per stack (multiplicative), cap 90 | wiki Attack speed | yes (`as_total%`) |
| Jinx R | 1700 -> 2500 u/s, damage by time | 1700 for 1350 u then 2200; damage 10% -> 100% by distance, full at 1500 u | jinx.bin, wiki | yes |
| Jinx W range | 1450 | 1500 | JinxWMissile | yes |
| Ezreal W hit radius | 60 | 80 | EzrealW mMissileWidth | yes |
| Lux Q cooldown | 11/10.5/10/9.5/9 | 10 at every rank | wiki Lux | yes |
| Master Yi W cost | 40 mana | 40 mana + 6% max mana per second, channel ends at 0 mana | masteryi_game.json | yes |
| Miss Fortune Love Tap -> Strut refund | flat 2 s | 2 s x cooldown multiplier | missfortune.bin | yes |
| Veigar W cooldown from stacks | capped at -50% | -10% per 50 stacks, no cap | wiki Veigar | yes |
| Yasuo passive shield | linear over levels | stat-progression scaled (L9 313, L20 674.5) | yasuo.bin | yes |
| Yasuo Flow, levels 7-12 | 52 per stack | 52.5 | wiki | yes |
| Yasuo crit damage / crit overflow | flat -5% of base, 0.05 AD per % | 95% of the total, 0.5 AD per % over 100% (classic) | wiki, YasuoCritToAD | yes |
| Yasuo Q3 knock-up | 1.0 s | 0.9 s | wiki | yes |
| Malphite Q speed steal | % of own move speed | flat MS equal to what the target lost | wiki | yes |
| Yasuo ARAM total attack speed +2.5% | folded into bonus AS | multiplier on total AS | wiki ARAM | yes (`as_total%`) |

Left: Darius R minion fear radius, Ahri R passive timing, Leona E dash landing, Jinx stack decay interval, Yasuo Q on-hit,
Lux R reveal (`Unit.is_revealed` missing), Sona Aria ARAM base heal (wiki 45-90 + 20% AP shield ratio; the installed `sona.bin`
differs, kept the bin).

### 5b. Items (stat conversion, price / recipe, passives; 195 shop items)

Stat conversion (`Stats.recompute` keys) and price / combine cost / recipe / total for all 195 shop items match the client file;
Dark Seal, Guardian Angel, Mejai's and Bastionbreaker are not in the shop. `tools/lol/extract_items.py` keeps the **classic ARAM**
`DataValuesModeOverride` block (`MODE_KEYS = ("ARAM",)`; verified in the data: Heartsteel 5%, Liandry's 1.8%, 75 s Maw / Locket cooldowns).
The engine does not inherit that block in Kiwi / Mayhem (Heartsteel 10%, Liandry's 2%, 60 s cooldowns): switch to `("Kiwi",)` and re-run if Mayhem is
turned on. Fixes that do not depend on the mode:

| Item | Ours (before) | League | Source | Fixed |
|---|---|---|---|---|
| Runaan's Hurricane bolt | 40% AD | 60% AD | bin calc, wiki V26.20 | yes |
| Hullbreaker Skipper | bonus HP, ranged 70% AD | max HP; ranged x0.7 of the melee formula | bin calc, wiki | yes |
| Hullbreaker Boarding Party | linear 70-130 | 70 +6/level from level 9 (130 at 18), ranged x0.5 | bin calc | yes |
| Manamune Awe | 2.5% bonus mana | 2% max mana | bin calc, wiki | yes |
| Actualizer | max mana | bonus mana | wiki | yes |
| Youmuu's ranged Wraith Step | 6 s | 4 s | bin calc | yes |
| Whispering Circlet cap | 60 | 360 bonus mana | wiki | yes |
| Manaflow upgrades | missing | Seraph's Embrace, Muramana, Fimbulwinter, Diadem of Songs at 360 bonus mana (`item_fx_x_upgrades.gd`) | bin, wiki | yes |
| ~25 tooltip values showing "?" | unresolved | resolved by the extractor | - | yes |

Left: Umbral Glaive Blackout reveal, Stat Bonus shard values in `aug_meta.gd` (augments are off), Essence Reaver refund
(client text vs wiki "half"), Yun Tal ranged crit per stack (data 0.5% vs wiki 0.4%).

## 6. Not verified / left

* Turret AD and resist ramps use the Tower Power-Up item numbers; the exact start second of the +3/min resist ramp (1:00 assumed) is inferred.
* First wave: data `InitialSpawnTimeSecs` 45 vs wiki ARAM 0:50 (kept 50).
* Overcharged HA (35:00 / 40:00 turret decay), Minion Pushing Power, Exhaust VFX, Darius R minion fear radius, Lux R reveal, Yasuo Q on-hit.
* Attacker reveal in fog (`ca_RevealAttackerRange` 400 / `ca_RevealAttackerTimeOut` 4.5 s in ARAM vs 300 / 2.0 on Summoner's Rift) is not implemented.
* Level-up health gain constants (`ai_levelUp_healthGainNetGain` 1.1, `...PercentMissingPenalty` 0.7) have unknown semantics; level-up HP still adds the max-HP difference.

## 7. Verification (2026-10-18, after all edits)

* `tools/numbers_check.sh`: `NUM DONE passes=130 fails=0` (formulas, structures, economy, summoners, minions; the AP-champion-vs-turret
  assertions fail on the old `Unit.attack_hit`).
* Kit tests (`kit_test_a.gd` x7, `kit_test_b.gd` x7): all `KIT DONE`, 0 `KIT FAIL`, 0 `SCRIPT ERROR`.
* Item harnesses (bruiser, marksman, mage, tank, support, upgrade, db): 0 failures.
* `--sim --time=600` seeds 11 / 22 / 33: exit 0, 0 `SCRIPT ERROR`.
