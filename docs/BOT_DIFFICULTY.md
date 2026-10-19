# Bot difficulty

Four tiers, modelled on League's bot tiers: **0 Intro, 1 Beginner, 2 Intermediate, 3 Hard** (`BotBrain.LEVEL_NAMES`).
Every bot has **its own** level. All behaviour lives in `src/ai/bot_brain.gd` (parameter table `BotBrain.LV`, plus `level`
checks inline) and `src/ai/team_ai.gd` (the team misjudges fights by the average of its bots' `judge_noise`). Small tagged
`[bot-diff]` hooks elsewhere: `summoners.gd` (summoner AI calls `ctx.*_decision`), `item_db.gd` (`bot_next_purchase` ->
`BotBrain.shape_build`), `augment_db.gd` (`bot_pick`), `match.gd` (`_bot_summoner`) and `game.gd` (`G.lineup`, default difficulty 2).

## How a bot gets its level

`BotBrain.level_for(champion)` resolves, in this order:

1. the **`G.lineup`** entry for the bot's `(team, champion)`;
2. `--botlevels=<ORDER level>,<CHAOS level>` on the command line (benchmarks and tests only);
3. `G.settings.difficulty` (default 2) for every bot.

### `G.lineup` structure (filled by champion select)

`G.lineup: Array` of 10 `Dictionary`, one per champion in the match, set before the match starts:

```gdscript
{"team": G.Team.ORDER,   # 0 = ORDER (the human's team), 1 = CHAOS
 "champion": "Ahri",     # alias, as in ChampionDB.ROSTER / Champion.alias
 "difficulty": 2}        # -1 = the human player, 0 Intro, 1 Beginner, 2 Intermediate, 3 Hard
```

An empty array means "every bot uses `G.settings.difficulty`". An entry with `difficulty` -1 (the human) is ignored by the AI (a sim's
`--botplayer` brain on the human falls back to rules 2 / 3). Entries are matched by `(team, champion)`, so the lineup must list the same
champions that `G.next_match` (`player_champion`, `ally_champions`, `enemy_champions`) starts. `BotBrain.set_level(n)` re-applies a level
to a live bot. `G.lineup` is not cleared by the match; champion select must reset it for every new match. `src/debug/bot_lineup_test.gd`
checks the resolution rules.

Allies are not special: every bot, ally or enemy, plays the level its lineup entry gives (or `G.settings.difficulty` without a lineup).

## What each level does

| Aspect | Intro (0) | Beginner (1) | Intermediate (2) | Hard (3) |
|---|---|---|---|---|
| Decision interval | 0.55 s, freezes 22% of decisions for 0.4-1.0 s | 0.38 s, freezes 12% | 0.26 s, freezes 5% | 0.10 s |
| Skillshot aim scatter | 2.0 m | 1.3 m | 0.8 m (x0.15 on rooted / stunned targets) | 0.04 m |
| Target leading | none (aims where the target is) | half the velocity | 80% of the velocity | follows the target's real move path, stops when it casts |
| Sidesteps incoming skillshots | never | 10%, reacts after 0.45 s | 30%, 0.3 s | 88%, 0.09 s |
| Ability use | skips 45% of casts, 1.2 s pause after a cast, ultimate 50% of the time | skips 30%, 0.6 s pause, ultimate whenever ready | skips 15%, 0.3 s pause; ultimate on 2+ enemies, a low-hp enemy or when hurt (waits at most 5 s) | never skips, 0.15 s pause; ultimate on multi-target / kills / engage (waits at most 8 s); casts crowd control first, holds it for engages and picks, never stacks CC on a locked-down target; keeps 30% mana in lane |
| Ability target | nearest enemy | lowest hp%, nearer first | lowest hp%, team focus | lowest effective hp, killable first, locked-down and ranged carries preferred |
| Fight target | nearest | hp%, small kill bonus | hp%, kill bonus, team focus, carries | + effective hp, isolated targets, full focus fire |
| Team focus fire | never | 20% of decisions | 50% | always |
| Team stance (engage) | never engages | engages 40% of the time | follows the team | follows the team |
| Misjudges fight strength | +-55% | +-45% | +-30% | never |
| Kiting / orb-walking | none (stand and trade) | 25% of attack cycles | 50% | every cycle, longer steps (88% of the attack timer) |
| Melee chase | gives up after 1.5 s | 2 s | 3 s | 4 s |
| Last hitting | attacks the nearest minion | 40% skilled | 75% | 100% |
| Positioning | stands at the front of the wave (30% of the normal distance behind it), walks in from far, tight spacing | 65% distance behind the wave | behind the wave | behind the wave (110%), more cautious spacing |
| Turret awareness | none (fights and farms under towers) | respects turret range in 50% of decisions | 75% | always; dives only to secure a kill (hp > 50%, minions tanking) or finish a low target |
| Pushing | no | no | no | with 2+ more champions alive than the enemy it sieges the turret without waiting for minions and ignores turret aggro while healthy |
| Retreat | below ~10% hp, short retreats, ignores turret aggro | 20% hp base, retreats when outnumbered alone | 28%, also when the team falls back | 32%, also on a numbers disadvantage or when a mana caster runs dry |
| Flash | never | escape below 12% hp | escape below 20%, secures kills on targets below 15% hp | escapes toward safety (also when burst-doomed), secures kills (target below burst), never into turrets |
| Heal / Barrier | at 10% hp | 20% | 28% (also heals allies below 22%) | 40% hp or when burst is about to kill (also allies below 32%); Barrier on heavy incoming damage |
| Cleanse | never | 40% of hard CCs | on hard CC when enemies are near | on hard CC |
| Ghost / Exhaust | never | Ghost | Ghost; Exhaust on a melee diver below 35% hp | Ghost; Exhaust on a melee diver below 55% hp (about 1 in 9 Hard bots brings Exhaust) |
| Mark (snowball) | never | at the nearest target, dash only to finish below 30% | with lead, dash on kills / engages | skipped when minions block the path |
| Ignite | never | targets below 20% hp | below 35% | targets that burn + half the burst will kill |
| Health relics | never | below 30% hp within 10 m | below 50% within 16 m | below 70% within 22 m |
| Item build | generic bruiser build whatever the champion; shops at most every 40 s | the curated build in a scrambled order; shop every 15 s | curated build | curated build |
| Augments | 70% random pick | 35% random pick | scored pick | scored pick |

Tuning: `--botlv=<level>:<key>=<value>[,...]` overrides an `LV` entry for every bot of that level (ablations, `tools/bot_bench.sh -x`).

## Benchmark

`tools/bot_bench.sh [-p "3:0 2:1 ..."] [-s "1 2 3"] [-t 900] [-j 8] [-o tag] [-x "extra args"]` runs headless bot-vs-bot matches
(`src/debug/bot_bench.gd` through `--botlevels=A,B`), each pairing on both sides for every seed (same seed = same champions per side, so
the roster / side bias cancels), then `tools/bot_bench_report.py` prints the table. A match ends at a nexus kill or at the time cap; an
undecided match is adjudicated by kills + structures destroyed (turret = 3, inhibitor = 6), a tie counts half a win. The mirror rows play
the same level on both teams: their "win" column is the ORDER side, i.e. the roster / side bias of the benchmark (not a skill measure).
Skillshot hit % counts skillshots launched with an enemy champion near their path.

Results (6 seeds, both sides, 720 s cap, `tools/bot_bench.sh -p "3:0 2:0 1:0 3:1 2:1 3:2 3:3" -s "1 2 3 4 5 6" -t 720`):

| Pairing | Matches | Higher level wins | Kills (hi : lo) | Damage to champions (hi : lo) | Skillshot hit % (hi : lo) |
|---|---|---|---|---|---|
| Hard vs Intro | 12 | **100%** | 46.6 : 14.5 | 88k : 39k | 41% : 16% |
| Intermediate vs Intro | 12 | **100%** | 49.8 : 18.4 | 99k : 45k | 38% : 21% |
| Beginner vs Intro | 12 | **100%** | 46.3 : 18.9 | 94k : 50k | 34% : 19% |
| Hard vs Beginner | 12 | **83%** | 36.8 : 22.2 | 70k : 49k | 39% : 22% |
| Intermediate vs Beginner | 12 | **83%** | 38.8 : 26.6 | 73k : 57k | 36% : 30% |
| Hard vs Intermediate | 12 | **62%** | 34.7 : 28.0 | 68k : 54k | 34% : 22% |
| Hard mirror (ORDER side) | 6 | 83% (roster / side bias) | 29.7 : 25.0 | 61k : 49k | 26% : 31% |

Per level, averaged over all runs (per team per match):

| Level | Skillshots launched | Hit % | Threatening shots | Sidestepped | Casts | Kills | Deaths |
|---|---|---|---|---|---|---|---|
| Intro | 189 | 19% | 175 | 0% | 261 | 17.3 | 57.1 |
| Beginner | 236 | 29% | 146 | 3% | 368 | 31.7 | 39.4 |
| Intermediate | 253 | 32% | 135 | 18% | 441 | 38.9 | 34.1 |
| Hard | 264 | 35% | 139 | 79% | 495 | 36.4 | 30.0 |

Notes: the Hard-vs-Intermediate gap is the smallest (Hard deals 26% more damage to champions and gets 24% more kills, wins 62% of the matches);
the gaps below it are large. Early tuning runs showed what matters most in this sim: turret awareness, orb-walking, reaction / hesitation,
fight misjudgement and accuracy; mana discipline, CC holding and ultimate patience were neutral. Per-bot CPU: `u.think` (all units) averages
~0.4-0.5 ms with ten Intro bots and ~0.6-0.8 ms with ten Hard bots (headless perf_probe, 150 s).
