# ARAM: Mayhem — Research Report & Design Bible

*Compiled 2026-10-17 for a single-player Godot recreation. Live patch at time of writing: **26.20** (client/Data Dragon 16.20.1); **26.21 ("Mayhem 4.0 / Journey to Stardom")** is on PBE, due ~21 Oct 2026.*

**How to read this document**

- Inline links point at the source of each key number. Link labels are short tags (for example [wiki][W-Mayhem]); the full URL list is at the end.
- **"Client data"** means values read from Riot's game files as mirrored by CommunityDragon ([map12.bin][CD-Map12], [kiwi.bin][CD-Kiwi], [string table][CD-Strings]), or from the local extraction at `D:\Games\ARAM_Mayhem\tools\extracted\client\kiwi_list.txt` ([client list][Client]). "Kiwi" is Riot's internal codename for ARAM: Mayhem.
- **"X–Y"** ranges in augment and spell text scale linearly with champion level 1→18 unless the text says otherwise.
- Places where sources disagree, or where something is my estimate or a design proposal, are marked **(conflict)**, **(estimate)** or **(proposal)**.

---

## 0. TL;DR — Mayhem at a glance

| Rule | Value | Source |
|---|---|---|
| Format | 5v5, all random, blind, no bans. Maps: Howling Abyss, Butcher's Bridge, Koeshin's Crossing | [wiki][W-Mayhem] |
| Start | Level **3**, **1,400 gold**. You choose your first augment as you spawn | [wiki][W-ARAM], [client][CD-Map12] |
| Passive gold | **42.5 gold every 5 s (8.5 g/s, 85 per 10 s)** from 1:00. Regular ARAM is 30 per 5 s (60 per 10 s) | [client][CD-Map12] |
| Passive XP | 5 XP/s (Howling Abyss aura) | [client][CD-Map12] |
| Augment screens | Game start (level 3), then levels **7, 11, 15**. That makes 4 slots, plus a 5th slot for a few special augments | [wiki][W-Mayhem] |
| Choices | **3 offers**. Each offer can be **rerolled once at the same tier**, so up to 6 augments seen per screen | [wiki][W-Mayhem], [client][CD-Map12] |
| Rarity | Silver < Gold < Prismatic. **Everyone gets the same tier on a given screen**, and the tier is random each screen. Rounds 1 and 2 can't both be Silver | [wiki][W-Mayhem], [patch history][W-Patch] |
| When you can pick | Only while the shop is open (dead, or on the spawn platform), and not while in combat (26.06). Missed screens queue up | [wiki][W-Mayhem], [patch history][W-Patch] |
| Pool size | **223 augments live** (62 Silver / 86 Gold / 75 Prismatic) | [client list][Client] |
| Global buffs | +20→600 (melee) or +20→400 (ranged) base HP by level; +15 armor and MR for melee; +10% mana/energy regen; Presence of Mind; **attack speed cap 5.0**; each 1% crit above 100% gives 0.45 AD or 0.75 AP | [wiki][W-Mayhem], [client][CD-Map12] |
| Anti-chain-CC | "Combo Breaker": tenacity on each new CC chain; if immobilized 5 of the last 7 s, cleanse plus 3 s CC immunity | [wiki][W-Mayhem] |
| Structures | Nexus **3,000 HP** (down from 5,500). Nexus turrets **3,000 HP** (up from 1,800). Inhibitor turret takes 40% less damage for 70 s after the outer turret falls | [wiki][W-Mayhem] |
| Relics | Area heal is **22% of missing HP and mana** (ARAM: 16%) | [wiki][W-Mayhem] |
| Minions | Siege minions give a +20% AS/MS aura. Only **1 super minion** per wave while an inhibitor is down | [wiki][W-Mayhem] |
| Runes and spells | Runes disabled (some keystones come from augments). Exhaust disabled. Flash optional since 26.03 | [wiki][W-Mayhem], [patch history][W-Patch] |
| Typical game length | About 10–20 min | [Inven][Inven] |

---

## 1. Core rules: ARAM: Mayhem vs. normal ARAM

### 1.1 Timeline of the mode (what changed when)

| Patch / date | Change | Source |
|---|---|---|
| **25.21 – 22 Oct 2025** | Launch with Trials of Twilight Act II. Riot described it as a "champion-first" ARAM with Arena-style augments: many Arena augments plus "over 40 brand-new" ones. Persistent always-on Arena effects were cut for readability, and auto-casting augments fire less often but hit harder. Augments are claimed on death, like items. Originally Wild Rift's "Hextech/AAA ARAM" | [Riot dev blog][Riot-Dev1], [wiki][W-Mayhem] |
| 25.22 | Big tuning pass (Draw Your Sword, Dual Wield, Glass Cannon, Laser Heal, Swift and Safe…) | [patch history][W-Patch] |
| 25.23 | Passive XP/gold retuned "to keep matches from ending too soon". Fewer Silvers in round 1, and rounds 1 and 2 can't both be Silver. No more extra super minion. **Stat Bonus anvil** added (750 g) | [patch history][W-Patch] |
| 25.24 | Crit above 100% converts to adaptive force. New: Cerberus, Earthwake, Orbital Laser, Pandora's Box, Stackosaurus Rex, Trueshot Prodigy. Some augments limited per team (Earthwake 2, Orbital Laser 1, Trueshot 1). New items: Hextech Gunblade, Sword of Blossoming Dawn | [patch history][W-Patch] |
| 26.01 (9 Jan hotfix) | Duplicate augments in multiple slots no longer possible | [patch history][W-Patch] |
| **26.03 – "Mayhem 2.0" (4 Feb 2026)** | Flash no longer mandatory, and summoner-spell augments let you choose the slot. **Mayhem Progression Track** (32 levels). **Augment Sets / "Traits"** (9 sets with 2/3/4-piece bonuses). About 45 new augments | [patch history][W-Patch], [arammayhem 26.3][AM-263] |
| 26.03 hotfixes | Level-4 "+300 starting gold" reward replaced by a Golden Reroll; Riot called it "not an exciting reward". Anvil level requirement raised from 9 to **16**. Several set nerfs | [patch history][W-Patch], [Reddit/Riot Cadmus][Reddit-Cadmus] |
| 26.05 | Nexus HP 5,500→3,000, nexus turret HP 1,800→3,000 | [patch history][W-Patch] |
| 26.06 | Augment screens no longer open while in combat | [patch history][W-Patch] |
| **26.12 – "Augmentmaxxing" (9 Jun 2026)** | **Sets/Traits removed** ("too much power sat behind Trait effects"). New **Ability Augments** (upgrade one of your spells) and more **Quest Augments**. 59 new augments, 30+ removed | [Riot dev blog 2][Riot-Dev2], [IBTimes][IBT-Hotfix] |
| 19 Jun 2026 hotfix | **450+ ability-augment/champion combinations stripped** because they did nothing or were bugged | [IBTimes][IBT-Hotfix] |
| 26.13 | Ability augments only offered on spells that benefit from them. Archmage became Prismatic, Quickstep became Gold. Assorted buffs and nerfs | [arammayhem 26.13][AM-2613] |
| 26.20 (live) | Tuning (Triggered Inferno, Shark Tempest, Squishy Slappy Grab, Juiced, Leg Day) plus Mayhem-specific champion buffs (Bard, Garen, K'Sante, Lee Sin, Swain, Thresh) | [arammayhem 26.20][AM-2620] |
| **26.21 (PBE, ~21 Oct 2026)** | **"Headliners"**: a music act per match with a game-wide effect (8 acts). New augments: Get Jinxed, Brass Blast, BEES!!!, Totentanz, Salvation. 14 augments reportedly removed | [arammayhem 4.0][AM-40], [GameRiv][GameRiv-2621] |

### 1.2 Rules inherited unchanged from ARAM

From the [ARAM wiki page][W-ARAM] unless noted:

- **Start:** level 3 with 0 XP towards level 4, and **1,400 gold** (client constant `ai_StartingGold = 1400` [client][CD-Map12]).
- **Passive gold** starts at **1:00** (`mission_AmbientGoldStartTime = 60`).
- **Passive XP:** 5 XP/s. The Howling Abyss aura also gives +70 summoner spell haste, a little mana regen and some melee-specific buffs.
- **No fountain regen and no Recall.** Health relics replace them (see §4.5).
- **Limited shopping:** you can buy only until you leave the shop area (slightly past the nexus turrets) or enter combat. The shop reopens only when you die.
- **Long-range damage reduction:** champions take 85%→70% damage from enemy champions 1,000→2,000 units away. DoTs and ultimates are excluded.
- **Late-game structure damage:** +0→25% bonus damage to structures from 18:00 to 30:00.
- **Surrender** from **8:00**, needs 4/5 votes (70%).
- **Respawn timer by level** (client `DeathTimes`): 9, 10, **11** (level 3), 13, 15, 17, 19, 21, 22, 24, 26, 28, 30, 32, 34, 36, 38, **40** (level 18) seconds. From **24:00** the timer grows +2.5% per minute, capped at +25% ([client][CD-Map12], [wiki][W-ARAM]).
- **Per-champion balance modifiers** (damage dealt/taken, healing, shielding, tenacity, ability haste). ARAM has its own table, and Mayhem adds another layer on top ([wiki][W-Mayhem]). For example, Mayhem 26.20 lowers Swain's damage taken from 105% to 100% and buffs Garen's W.
- **Snowball (Mark/Dash):** throw a 1,600-range skillshot for **15–100 true damage** (10 + 5 per level), then recast within 3 s to dash to the target. Base CD 80 s, effectively about **48 s** with the 70 summoner haste aura ([wiki Mark][W-Mark], [Mobafire][Mobafire-Mark], [Data Dragon][DDragon]).
- **Poro-Snax** sit in the trinket slot: 1 charge at start, +1 on your team's first turret kill. **Cappa Juice** and **Guardian's** starter items (950 g) exist.
- **Champion select:** each player is offered 2 random champions (sometimes a 3rd "blessed" card) and can swap with the bench.
- **Kill gold** (client kill-bounty config, the same for ARAM and Kiwi): `BaseGold 200`, first blood +90, assist pool 90, bounty can grow to +600 over base at 1 bounty gold per 2 gold earned, and depreciates at 1 per 4 gold distributed ([client][CD-Map12]). **(conflict)** The [ARAM wiki][W-ARAM] still lists **180** base gold. Early-game bounties are cut to 50% and ramp to 100% between 1:30 and 3:30 ([wiki][W-ARAM]; the client value 210 s matches).

### 1.3 Mayhem-specific changes (on top of ARAM)

| System | ARAM | ARAM: Mayhem | Source |
|---|---|---|---|
| Passive gold | 30 g / 5 s | **42.5 g / 5 s** (+42%) | [client][CD-Map12] |
| Attack speed cap | 3.0 (`gcd_AttackMinDelay 0.333`) | **5.0** (`0.2`) | [client][CD-Map12], [wiki][W-Mayhem] |
| Runes | Normal runes | **Disabled.** Keystones come only from augments (From Beginning To End, Impassable, Symphony of War) | [wiki][W-Mayhem] |
| Summoner spells | Exhaust allowed | **Exhaust disabled.** Mayhem-only spells come from augments | [wiki][W-Mayhem] |
| Base HP bonus | – | +20 → +600 (melee) / +20 → +400 (ranged), linear: `20 + (580/17)·(lvl−1)` for melee | [wiki raw][W-Mayhem] |
| Armor/MR bonus | – | +15 (melee) / +2→25 (ranged, by level). **Bug:** ranged champions currently get none | [wiki][W-Mayhem] |
| Resource regen | – | +10% mana/energy regen | [wiki][W-Mayhem] |
| Presence of Mind | – | Given to everyone | [wiki][W-Mayhem] |
| Crit overflow | Wasted | Each 1% above 100% gives 0.45 bonus AD or 0.75 AP (adaptive) | [wiki][W-Mayhem] |
| Combo Breaker | – | Each immobilize that starts a new CC chain grants tenacity for 3.25 s (the wiki shows "X%"; value unknown). If immobilized 5 of the last 7 s: cleanse and **3 s CC immunity** | [wiki][W-Mayhem] |
| Nexus / nexus turrets | 5,500 / 1,800 HP | **3,000 / 3,000 HP** (games end faster once the base breaks) | [wiki][W-Mayhem] |
| Inhibitor turret backdoor | 35% DR for 60 s | **40% DR for 70 s** after the outer turret dies | [wiki][W-Turret], [wiki][W-Mayhem] |
| Super minions | Up to 2 per inhibitor down | **1 per wave** while the inhibitor is down | [wiki][W-Mayhem] |
| Siege minions | – | Aura: +20% AS and +20% MS to nearby allied minions | [wiki][W-Mayhem] |
| Relic area heal | 16% missing HP/mana | **22%** | [wiki][W-Mayhem] |
| Unit→champion damage ratio | `dr_UnitToHero 0.5` | `1.0`. Probably the damage multiplier for non-champion units hitting champions; my interpretation, unverified | [client][CD-Map12] |
| Item shop | ARAM list | Adds Atma's Reckoning, Rite of Ruin, Sword of Blossoming Dawn, Stat Bonus (anvil), plus quest-reward items | [wiki][W-Mayhem] |
| Item overrides | – | Blade of the Ruined King on-hit 9% (melee) / 6% (ranged) current HP. Heartsteel permanent HP = 10% of damage. Shieldbow, Maw, Shurelya's and Sterak's CD 60 s. Wooglet's stasis CD 60 s | [wiki raw][W-Mayhem] |
| Keystone overrides | – | Aftershock CD 15 s, Glacial CD 15 s, Conqueror 3–5.5 adaptive per stack, Dark Harvest 50–100 base +20 per soul, First Strike +10%. Lethal Tempo loses its bolt but gives +50 range and raises the AS cap to 10 at max stacks | [wiki raw][W-Mayhem] |
| Omnivamp/vamp on AoE, pets, DoT | – | Both modes use 33.3% effectiveness for AoE/pet (and DoT for omni/spell vamp) and vs minions/monsters | [client][CD-Map12] |

### 1.4 The augment system in detail

**Slots and timing** ([wiki][W-Mayhem], [Riot support][Riot-Support])
- **Four regular slots** are filled by the selection screens at game start (level 3), level 7, level 11 and level 15. A **fifth slot** exists only for "a select few special augments", meaning the ones that grant other augments or summoner spells.
- **Screens only appear while the shop is enabled**: when you are dead, or on the spawn platform right after respawning. If you hit a level while out in lane, the screen is held until you next die. Several pending screens are offered one after another, in order.
- Since 26.06 a screen will not open while you are **in combat**. You can hide a screen, but the shop stays locked while it's hidden.
- In practice your first augment is chosen on spawn, and every later augment comes **after a death**. Dying is therefore a power-up moment, which is a big part of the mode's rhythm.

**Offers, rarity and rerolls**
- **3 offers per screen.** In client data the Kiwi augment-selection config sets the offer count to 3 for every rarity (`{0:3, 1:3, 2:3}`), and holds **fallback pools** per rarity (8 Silver, 7 Gold, 18 Prismatic) used when the normal pool runs dry ([client][CD-Map12]).
- **The tier is rolled once per screen and is the same for all 10 players** ("Every player is offered the same tier of augments in each selection screen; the tier itself is random each time", [wiki][W-Mayhem]). Silvers are rarer in round 1, and rounds 1 and 2 can't both be Silver ([patch history][W-Patch]).
- **Exact tier odds are not published.** I found no official numbers on the wiki, in patch notes or on stat sites, and they are not in the client data either. See the weights proposed below.
- **Reroll:** each of the 3 offers has its own **one-time reroll** to another augment of the same tier, so you can see up to 6 augments.
- **Golden Reroll** (progression level 1): sometimes appears on one offer in Silver or Gold screens. Using it rerolls that offer **one tier higher**.
- **No repeats:** once an augment has been shown it won't be offered again that game, and you can't own duplicates (26.01).
- **Champion filtering:** Ability Augments only roll on champions with a matching ability (knockback, missile, dash and so on). Since 26.13 they only appear on spells that actually benefit from them ([arammayhem 26.13][AM-2613]).
- **Per-team caps:** some augments are limited per team per game. Earthwake max 2; historically Orbital Laser, Trueshot Prodigy, Poro Blaster and Droppybara max 1 ([wiki augments][W-AugData]).
- **Unlocks:** some augments are locked behind the progression track. A newly unlocked non-Silver augment is guaranteed to appear in your next match if it fits the draft ([Riot support][Riot-Support]).
- **Meta-augments:** Transmute: Gold/Prismatic/Chaos and Pandora's Box generate other augments. Stats! line augments give anvils, and Stats on Stats on Stats! adds an extra reroll per slot next round. King Me grants a Prismatic later in the game.

**(proposal) Tier weights for the recreation.** Rarity is rolled once per screen and shared by the player and all 9 bots.

| Screen | Silver | Gold | Prismatic | Constraint |
|---|---|---|---|---|
| 1 (start, level 3) | 15% | 55% | 30% | – |
| 2 (level 7) | 30% | 45% | 25% | Never Silver if screen 1 was Silver |
| 3 (level 11) | 30% | 40% | 30% | – |
| 4 (level 15) | 25% | 40% | 35% | – |
| Golden Reroll | Shown on about 20% of Silver/Gold screens, on one random offer | | | |

### 1.5 Augment Sets ("Traits"), 26.03 → 26.11, now removed

These are documented because they are a good optional system to bring back. Source: [wiki Old content][W-Old].

| Set | Members (at removal) | 2 pieces | 3 pieces | 4 pieces |
|---|---|---|---|---|
| **Archmage** | Buff Buddies, Juiced, Mind to Matter, Ocean Soul, Overflow | Casting an ability refunds **30%** of its cooldown to another random ability | – | – |
| **Dive Bomb** | Clown College, Dive Bomber, Final City Transit, Self Destruct | **−25%** death timer | – | – |
| **Firecracker** | Critical Missile, Fan the Hammer, Light 'em Up!, Magic Missile, Twin Fire, Typhoon | "Firecracker" missiles bounce **2×** at 25% damage | – | 3 bounces at 50% |
| **Fully Automated** | Divine Intervention, Firefox, Frost Wraith, OK Boomerang, Prom Queen, Quantum Computing, Self Destruct, Sonata | Auto-cast augments get **−30%** cooldown | Their cooldowns also scale with your ability haste | – |
| **High Roller** | Pandora's Box, Stats!, Stats on Stats!, Stats on Stats on Stats!, Transmute ×3 | Enemy minion deaths have a **9%** chance to drop a Stat Anvil | +20% chance of Gold/Prismatic anvil rolls | +50% (70% total) |
| **Make it Rain** | Donation, From Beginning to End, Goldrend, Heads Up Cupcake!, Red Envelopes, Upgrade Collector, Upgrade Immolate | Takedowns drop **6 coins** (5 g each) | 12 coins | – |
| **Snowday** | Biggest Snowball Ever, Holy Snowball, Pinball, Snowball Roulette, Snowball Upgrade | Mark +30% damage, +50 summoner haste | +50%, +100 haste | +100%, +150 haste |
| **Stackosaurus Rex** | Infinite Recursion, Master of Duality, Phenomenal Evil, Steel Your Heart, Shrink Engine, Slap Around, Soul Eater, Tap Dancer, Upgrade Hubris | **+50%** permanent stacks from abilities | +100% | +200% |
| **Wee Woo Wee Woo** | All For You, Critical Healing, First-Aid Kit, I'm a Baby Kitty…, Sonata, Upgrade Mikael's, Windspeaker's Blessing | +50% MS towards allies below 50% HP within 650 | Next heal/shield also heals 12% of missing HP (10 s CD) | – |

The one "set" that survives is hidden: owning **Bread And Butter + Bread And Jam + Bread and Cheese** gives **"Bread Sandwich": +250 ultimate haste and +50 ability haste on each basic ability** ([wiki augments][W-Aug]).

Why Riot removed sets: power sat in the set bonus rather than in individual augments, builds converged ("made builds feel similar"), and players who missed the second piece were stuck with weak augments ([Riot dev blog 2][Riot-Dev2], [IBTimes][IBT-Hotfix]).

### 1.6 Stat Anvils ("Stat Bonus" item)

- **Cost 750 g. Requires level 16** (raised from 9 in a 26.03 hotfix; the item page still says 9). Each purchase also gives a free Cappa Juice and a hat ([patch history][W-Patch], [wiki][W-Mayhem]).
- Opening an anvil shows a semi-random choice of **Stat Shards** in three tiers ([wiki anvil][W-Anvil]):
  - **Silver:** 11 AH / 15 AP / 12 armor / 11 AD / 11% AS / 8% crit / 110 HP / 8 lethality / 8 magic pen / 14 MR / (8 AD + 12 AP) / (10% AS + 8 AH) / (10 armor + 10 MR).
  - **Gold:** 35 AH / 50 AP / 45 armor / 35 AD / 35% AS / 25% crit / 375 HP / 20 lethality / 18 magic pen / 45 MR / (25 AD + 25 AP) / (25% AS + 20 AH) / (30 armor + 30 MR).
  - **Prismatic:** 17.5% armor pen / +25% crit damage / +15% max HP and +10% size / 17.5% magic pen / +18% MS and −10% size / 20% (melee) or 10% (ranged) omnivamp / +25% heal & shield power / 30% tenacity.
- Anvils also come from augments: Stats! (2), Stats on Stats! (3), Stats on Stats on Stats! (4, better odds), High Roller (random drops), and the progression-track "Anvil Voucher" (a free anvil at game start).

### 1.7 Mayhem-only summoner spells and items

| Spell | Effect (client data) |
|---|---|
| **Growth Spurt** | 76.5 s CD. Grow +50% size, knock up and back enemies within 400 (1 s, 275 units), +300 max HP for 7 s ([client][CD-Kiwi]) |
| **Poltergeist** | 68 s CD. Casts Barrier and Ghost together (Ghost +30% MS for 5 s) |
| **Poro Charge** | 120 s CD. Waves of Poros, first wave slows 85% for 2 s (from Poro Stampede) |
| **When the Darkness Comes** | 180 s CD. 500-radius light sends everyone hit into a private realm for 8 s, where you get bonus stats (from Dimension Shift) |
| Others granted by augments | Flash (Flash 2 / Flashy / Flashbang), Vigilance (Empyrean Promise), Blade Waltz, Heroic Swing (Spin Me Right Round), Deceive (Clown College); in 26.21, Get Jinxed / Brass Blast / Totentanz |

**Items:** Atma's Reckoning (2,900), Rite of Ruin (3,000), Sword of Blossoming Dawn (2,350), Stat Bonus (750). Quest rewards: The Golden Spatula (Urf's Champion), Ultra Hydra, Void Immolation (Icathia's Fall), Wooglet's Witchcap, Jarvan I's (Sneakerhead). Prices from [Data Dragon][DDragon]; details in §6.

### 1.8 Progression track, quests, events

- **Mayhem Progression Track:** 32 levels earned with Mayhem XP (1 MXP per minute played plus daily, weekly and one-time missions; about 9,000 MXP total). It is free ([Riot support][Riot-Support]).
  - Rewards include a Golden Reroll chance (level 1), a better chance of a 3rd "blessed" champion card (level 5), more Ability-augment offers (level 9), Rainbow Crystal Candy replacing Poro-Snax (level 13), an Anvil Voucher (level 18), elixir/potion drops (level 23), and augment unlocks such as Poro Stampede (level 30) and Dimension Shift (level 32) ([wiki][W-Mayhem], [arammayhem 26.3][AM-263]).
- **Quest augments** (client `ModesQuestData` milestones, [client][CD-Kiwi]):

| Quest augment | Milestones |
|---|---|
| From Downtown | 15 long-range hits |
| Steel Your Heart | 300 Heartsteel HP |
| Multishot | 50 / 250 / 700 / 2,000 / 4,000 / 8,000, divided by the ability's base CD |
| Urf's Champion | 18 takedowns |
| Pressure Cooker | 1,500 / 15,000 / 30,000 burn damage |
| Poro Stampede | 5 / 12 / 20 / 30 / 44 / 63 / 90 / 129 / 187 / 275 Poros fed |
| Pursuit of Power | 10 hits |
| Pursuit of Haste | 10 / 30 hits |
| Wooglet's Witchcap, Icathia's Fall | 2 items |
| Ultra Hydra | 3 items |
| Support Main | 3,000 healing |

- **"Headliners" (26.21, PBE):** one of 8 music acts takes the stage each match and adds a game-wide rule ([arammayhem 4.0][AM-40]):
  - **True Damage:** multikills, shutdowns and towers give anvils.
  - **HEARTSTEEL:** "stickered" augments give bonuses.
  - **K/DA:** collect photocards to earn an extra augment.
  - **Pentakill:** empowers a basic ability, and another at level 18.
  - **Cafe Cuties:** stronger relics with movement speed.
  - **Command Line:** your first reroll each screen also raises the rarity.
  - **Space Groove:** dancing gives everyone gold.
  - **The Bee Band:** collect honey and avoid the bees.

  This is the clearest template for an "events" layer in the recreation.

---

## 2. Augment catalogue: all 223 live augments (patch 26.20)

**Backbone:** the 223 names and rarities come from the local client extraction ([client list][Client]: 62 Silver / 86 Gold / 75 Prismatic). Effect text is condensed from the LoL Wiki's augment data module as of 26.20 ([wiki data][W-AugData]) and cross-checked against client data where noted.

222 of the 223 names were found on the wiki. **Support Main** is the only augment the wiki lacks, so its text is reconstructed from client data ([client][CD-Kiwi], [strings][CD-Strings]). Two tier conflicts exist (BONK! and Terror: the client says Gold, the wiki says Silver); the client is used. The wiki additionally lists **Guilty Pleasure** (Silver: immobilizing a champion heals 30–250 (+1.5% max HP), 5 s CD), which is **not** in the live client list, so it's treated as removed.

Tags in *italics*: *disabled in live* = present in the data but currently turned off; *slated for removal in 26.21* = from the PBE removal list ([arammayhem 4.0][AM-40]). Ranges scale with level 1→18 unless stated. "bAD" = bonus AD.

**Community strength snapshot (26.20, [arammayhem tier list][AM-Tier]):** the S+ picks are Transmute: Prismatic, Shrink Engine, Recursion, Draw Your Sword and Tank Engine. Next come Infinite Recursion, Warlock Juicebox, Steel Your Heart, Critical Missile, Soul Siphon, Blunt Force, Phenomenal Evil, Eureka, Ethereal Weapon, Heavy Hitter, Back To Basics, Vulnerability and From Beginning To End. At the bottom (D) are Flash 2, Pin Cushion, Snowblast, Spin Me Right Round, Glass Cannon, Dimension Shift, Poro Stampede and King Me. Simple, always-useful stat augments win the most; flashy niche ones are what players remember.

**Tier "feel" guide:**
- **Silver:** a flat stat or a simple conditional effect.
- **Gold:** a strong stat package, or a mechanic that changes how you play.
- **Prismatic:** build-defining. It transforms the champion, adds a new ability, breaks a rule (no ultimate, melee conversion, revive), or scales without limit.

### 2.1 Stat sticks & stat conversions (24: 14S / 7G / 3P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **ADAPt** | Silver | Convert all of your bonus attack damage into ability power at a rate of 1 ability power per 0.6 bonus attack damage. Additionally, increase your ability power by 15%. |
| **Blunt Force** | Silver | Increases attack damage by 20%. |
| **Crit 'n Cast** | Silver | Gain ability haste equal to 40% of your critical strike chance. *[slated for removal in 26.21 (PBE)]* |
| **Deft** | Silver | Grants 60% bonus attack speed. |
| **Don't Blink** | Silver | Deal 1% increased damage per 10 movement speed you have more than the target. |
| **Erosion** | Silver | Each instance of damage dealt to an enemy reduces their armor and magic resistance by 1.5% for 4 seconds, stacking up to 20 times for a total of 30% resistances reduction. |
| **First-Aid Kit** | Silver | Grants 20% heal and shield power. |
| **Forged By The Master** | Silver | Increases the damage dealt by your item effects and augments by 45%. |
| **Goredrink** | Silver | Gain 15% omnivamp. |
| **Purist - Caster** | Silver | Convert all of your bonus attack speed into ability haste at a rate of 0.65 ability haste per 1% bonus attack speed. Additionally, your abilities' total cooldowns are reduced by 10%. |
| **Scoped Weapons** | Silver | Gain 75 (melee) / 50 (ranged) bonus attack range. |
| **Witchful Thinking** | Silver | Grants 20-80 ability power. |
| **Zealot** | Silver | Gain 35% (+ 5% per 100 AP) bonus attack speed and 25% (+ 5% per 100 AP) critical strike chance. |
| **escAPADe** | Silver | Convert all of your ability power into bonus attack damage at a rate of 1 bonus attack damage per 1.66 ability power. Additionally, increase your total attack damage by 15%. |
| **Apex Inventor** | Gold | Grants 100 item haste, which is equivalent to 50% cooldown reduction for items. |
| **Hide on Bush** | Gold | While in brush, you deal 20% increased damage. This effect lingers for 2 seconds after leaving brush. *[slated for removal in 26.21 (PBE)]* |
| **It's Critical** | Gold | Grants 50% critical strike chance. |
| **Recursion** | Gold | Grants 60 ability haste. |
| **Scopier Weapons** | Gold | Gain 200 (melee) / 100 (ranged) bonus attack range. |
| **Thread the Needle** | Gold | Grants 18% armor penetration and magic penetration. |
| **Warlock Juicebox** | Gold | Gain 10% (+ 3% per 100 AP) omnivamp. |
| **Eureka** | Prismatic | Gain ability haste equal to 30% AP. |
| **Protein Shake** | Prismatic | Gain 25% (+ 35% per 100 bonus armor) (+ 35% per 100 bonus magic resistance) heal and shield power. |
| **Scopiest Weapons** | Prismatic | Gain 250 (melee) / 150 (ranged) bonus attack range. |

### 2.2 Infinite scaling / stackers (the snowball engines) (11: 2S / 5G / 4P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Slap Around** | Silver | Immobilizing or grounding an enemy champion grants you 10 adaptive force (bonus AD x0.6 or AP), stacking infinitely (5 second cooldown per cast instance). Lose 50% of stacks on death. |
| **Stackosaurus Rex** | Silver | Increase the number of permanent stacks you gain from abilities by 100%. |
| **Phenomenal Evil** | Gold | Veigar's passive: each ability-damage hit on a champion grants a permanent +1 AP stack (max 1/s globally, 1 per 3 s per cast). If this is not your first augment you start with 40 stacks. |
| **Shrink Engine** | Gold | Scoring a champion takedown generates a stack, stacking infinitely. For each stack, gain 8 ability haste and 1% bonus movement speed, and reduce your size by 4%. Lose 65% of stacks on death. Size reduction is capped at 80% (20 stacks). |
| **Soul Eater** | Gold | Immobilizing or grounding an enemy champion grants you 20 bonus health, stacking infinitely (5 second cooldown per cast instance). If this is not your first augment, gain 300 bonus health. |
| **Tank Engine** | Gold | Scoring a champion takedown generates a stack, stacking infinitely. For each stack, increase your maximum health and size by 5%. Lose 65% of stacks on death. |
| **Tooth Fairy** | Gold | When you deal post-mitigation damage to an enemy champion equal to or more than 25% of their maximum health within 2.5 seconds, they drop a Tooth on the ground (4 second cooldown per target). You can pick up this Tooth by moving over it, granting you a Dental Records stack. For each stack, you gain 3 lethality and flat magic penetration. |
| **Infinite Recursion** | Prismatic | Gain 60 ability haste, increased by 3 each time you score a champion takedown. |
| **Master of Duality** | Prismatic | Basic attacks on-hit grant 6-18 ability power and damaging abilities once per cast instance grant 3-9 bonus attack damage, lasting for 5 seconds, with the duration of both refreshing on subsequent hits, and stacking infinitely. |
| **Tap Dancer** | Prismatic | Basic attacks on-hit against enemy champions and minions grant 10 bonus movement speed, lasting for 5 seconds, refreshing on subsequent triggers, and stacking infinitely. Additionally, gain bonus attack speed equal to 10% total movement speed. |
| **Titan's Resolve** | Prismatic | Every damage instance dealt or taken (non-DoT) gives a Juggernauting stack (6 s). Per 10 stacks: +15-45 bonus AD or 25-75 AP (adaptive), +5-10 armor & MR, +10% size, +8% tenacity. |

### 2.3 Cooldown manipulation & ultimate empowerment (15: 1S / 2G / 12P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Ultimate Unstoppable** | Silver | Casting your ultimate ability grants you crowd control immunity for 3 seconds (8 second cooldown). |
| **It's Killing Time** | Gold | Upon casting your ultimate ability, you apply Death Mark to all enemy champions (8 second cooldown). The mark stores 40% of all post-mitigation damage you deal to the affected target, detonating after 5 seconds to deal true damage equal to the damage stored against them. |
| **Skilled Sniper** | Gold | Hitting an enemy champion with a basic ability while located at least er 600 units away from them at the time of the hit reduces its current cooldown by 80% of its total cooldown, modified to 65% for damage over time abilities. |
| **Archmage** | Prismatic | Whenever you cast an ability, refund the cooldown of another, randomly selected ability by 30% of the casted ability's cooldown. |
| **Back To Basics** | Prismatic | Your champion abilities deal 35% increased damage and you gain 70 ability haste and 35% increased healing and shielding from all sources, but your ultimate ability is permanently sealed. |
| **Can't Touch This** | Prismatic | Casting your ultimate grants you invulnerability for 2 seconds (8 second cooldown). |
| **Dashing** | Prismatic | Abilities with dashes or blinks gain 175 ability haste. |
| **Fey Magic** | Prismatic | Damaging enemies with your ultimate ability polymorphs them into harmless critters for 2 seconds, during which their base movement speed is reduced by 60, and disarms them for the same duration (15 second cooldown per target). |
| **Final Form** | Prismatic | Casting your ultimate ability empowers you for 10 seconds, causing you to gain a shield for 50% of your maximum health, 20% omnivamp, and 30% bonus movement speed for the duration (20 second cooldown). |
| **Mystic Punch** | Prismatic | Basic attacks on-hit reduce the remaining cooldowns of your abilities by 1.25 seconds. |
| **Stuck In Here With Me** | Prismatic | Casting your ultimate gives you a 2 s aura that grows to 500 units, then taunts every enemy inside for 2 s while you take 50% less damage (30 s CD). Also +30 ultimate haste. |
| **Surge Field** | Prismatic | Casting your ultimate spawns a 300-radius surge zone under you: while inside you get +50 ability haste, +40% MS, and damage to champions fires missiles for 20% of the triggering hit (pre-mitigation) as bonus magic. The zone follows you once, then vanishes if you leave for 1.25 s. |
| **Ult Bot** | Prismatic | Ability haste now only affects your ultimate. In return gain 100 ability haste, and your ability/ultimate haste is 50% more effective (applied in the ult CD calculation). *[slated for removal in 26.21 (PBE)]* |
| **Ultimate Awakening** | Prismatic | Casting your ultimate ability resets the cooldowns of all your basic abilities and grants you 300 basic ability haste for 15 seconds (20 second cooldown). Additionally, gain 30 ultimate haste. |
| **Ultimate Revolution** | Prismatic | Casting your ultimate ability resets its cooldown once its effect starts or has elapsed (75 second cooldown, reset upon death). |

### 2.4 Basic attacks, on-hit & crit (15: 6S / 5G / 4P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Heavy Hitter** | Silver | Basic attacks deal bonus physical damage equal to 3.5% of your maximum health. |
| **Juiced** | Silver | Basic attacks vs champions deal bonus magic on-hit = 7% (melee) / 5.6% (ranged) of your max mana; this can crit (+30% IE-style bonus). No longer drains mana (26.20). |
| **Light 'Em Up!** | Silver | Basic attacks build stacks; the 4th attack fires 4 missiles at the target, each 11-80 (+35% bonus AD) (+19% AP) bonus magic on-hit (total 44-320 (+140% bAD) (+76% AP)). |
| **Tank It Or Leave It** | Silver | Gain Critical Defend Chance equal to 100% critical strike chance, up to 50%. Additionally, gain 25% critical strike chance. Critical Defend Chance: Grants you a chance to reduce an instance of damage taken by 20% (5 second cooldown per enemy spell cast instance). |
| **Twin Fire** | Silver | Damaging abilities against enemy champions launch 1 (+ 1 per 33.33% critical strike chance) missiles at the target that each deal 10-30 (+ 7% bonus AD) (+ 7% AP) magic damage (5 second cooldown). Additionally, gain 25% critical strike chance. |
| **Typhoon** | Silver | Basic attacks launch a missile at a nearby enemy, prioritizing champions, that deals 30% AD physical damage and applies on-hit effects. |
| **Critical Missile** | Gold | Critical strikes against enemy champions launch 1 (+ 1 per 50% critical strike chance) missiles at the target that each deal 15-65 magic damage. Additionally, gain 25% critical strike chance. *[slated for removal in 26.21 (PBE)]* |
| **Critical Rhythm** | Gold | Your critical strikes grant you 6% bonus attack speed for 6 seconds, stacking up to 10 times for a total of 60%. Additionally, gain 25% critical strike chance. |
| **Ethereal Weapon** | Gold | Your abilities apply on-hit effects (1 second cooldown per target). |
| **Marksmage** | Gold | Basic attacks deal bonus physical damage equal to 75% AP. |
| **Soul Siphon** | Gold | Heal for 12% of the post-mitigation damage dealt by your critical strikes. Additionally, gain 25% critical strike chance. |
| **Double Tap** | Prismatic | Basic attacks that critically strike apply on-hit effects an additional time. Additionally, gain 25% critical strike chance. |
| **Draw Your Sword** | Prismatic | Ranged champions only. Become melee (attack range 200 + bonus range from augments) and gain 24-100% bonus AD, 20-100% bonus AS, 24-100% bonus HP, 20-100% bonus MS and 20% life steal - the bonus is larger the longer your original range (scaled over 500-650 range). |
| **Dual Wield** | Prismatic | Your basic attacks launch a bolt at the target that fires after a 0.225-second delay on-attack, deals 40% of the triggering attack's pre-mitigation damage, and applies on-hit effects at 40% effectiveness. Additionally, increase your total attack speed by 10%. |
| **Fan The Hammer** | Prismatic | Your first attack on a champion from each cardinal direction (N/E/S/W; 5 s CD per direction) fires 5 extra missiles, each 8-51 (+14% bonus AD) physical (+0-50% by range), can crit, on-hit at 20%. *[slated for removal in 26.21 (PBE)]* |

### 2.5 Spell damage, true damage & burns (14: 1S / 7G / 6P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Ice Cold** | Silver | Your slowing effects reduce the movement speed of targets by an additional 75. |
| **Combusting Interest** | Gold | Gain 1-3 (+ 0.75% of damage dealt) gold for each tick of damage dealt to enemy champions with damage over time effects. *[slated for removal in 26.21 (PBE)]* |
| **Firebrand** | Gold | Basic attacks apply a Burn for 5 seconds that deals bonus magic damage equal to 2/5% of the target's maximum health per second.This Burn stacks infinitely and refreshes with each application. |
| **Magic Missile** | Gold | Dealing damage to an enemy champion with an ability fires 3 missiles at them that each deal true damage equal to 0.33% of the target's maximum health, increased to up to 1% based on distance travelled (maximum damage reached at 1000 units). This effect can only trigger once every 6 seconds from the same cast. |
| **Overflow** | Gold | Your abilities' mana costs are doubled, but you also gain 10% (+ 0.5% per 100 maximum mana) increased damage as well as self and outgoing healing and shielding. |
| **Pressure Cooker** | Gold | Burn aura: every second enemy champions within 300 get a stacking 3 s Burn of 0.5% of YOUR max HP per second. Quest tiers at 1,500 / 15,000 / 30,000 Burn damage: radius 500 -> double application rate -> radius 600. |
| **Spiritual Purification** | Gold | Scoring a champion takedown causes the area around the slain champion to explode in a 500 unit radius, dealing adaptive damage to enemies within equal to 15% of their current health and leaving behind a zone for 1.5 seconds that slows enemies within by 60%. *[slated for removal in 26.21 (PBE)]* |
| **Vulnerability** | Gold | Damage from items and damage-over-time effects can crit for (145% + bonus crit damage) (5 s CD per cast instance); +25% crit chance. If you also own Jeweled Gauntlet only the better crit-damage roll applies. |
| **Cruelty** | Prismatic | Immobilizing or grounding an enemy champion summons a comet above them that lands at their current location after 1 second, dealing 50-150 (+ 40% AP) (+ 4% of your maximum health) magic damage to enemies within a 300 radius (6 second cooldown per cast instance). For displacement effects, the comet will be summoned at the displacement's end location. |
| **Dropkick** | Prismatic | Attacks/abilities execute champions below 4% (+5.5% per 100 base AD) (+1% per 1000 bonus HP) max HP; the corpse is kicked away and explodes on hitting a champion or wall for 150-500 (+100% bonus armor) (+100% bonus MR) magic (can chain more executes). Each execute heals 100-300 (+25% bonus HP). *[slated for removal in 26.21 (PBE)]* |
| **Glass Cannon** | Prismatic | You gain a health threshold equal to 70% maximum health which cannot be modified nor exceeded by any means. In return, you deal bonus true damage equal to 25% (melee) / 15% (ranged) of all of the damage you deal pre-mitigation. |
| **Infernal Conduit** | Prismatic | Ability hits on champions apply a stacking 3 s Burn: 2-20 (+4.6% bonus AD) (+2% AP) magic per second (6-60 total per stack; 1 s CD per cast). EVERY Burn tick you deal (any Burn source) reduces your basic ability cooldowns by 0.08 s. |
| **Jeweled Gauntlet** | Prismatic | Your abilities can now critically strike for (145% + bonus critical damage) damage. Additionally, gain 25% (+ 4.5% per 100 AP) critical strike chance. If both Jeweled Gauntlet and Vulnerability are equipped, only rolls the critical strike chance of the augment that has the higher critical damage (or either if equal). |
| **Ominous Pact** | Prismatic | Abilities cost 5% of current HP. Gain AP based on missing HP (up to 75-150 at 70% missing), plus 0-50% bonus MS and 0-20% omnivamp scaling with missing HP. |

### 2.6 Tank, size & survival (20: 7S / 8G / 5P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Adamant** | Silver | Immobilizing or grounding an enemy champion grants 10 bonus armor and bonus magic resistance for 10 seconds, stacking up to 10 times for a total of 100 bonus resistances, and refreshing on subsequent triggers (5 second cooldown per cast instance). *[disabled in live (wiki)]* |
| **Don't Change the Channel** | Silver | For every second that you channel an ability, you gain a 50-200 (+ 50% AD) (+ 25% AP) (+ 10% bonus health) shield. The shield quickly decays once you stop channeling. |
| **Escape Plan** | Silver | Upon dropping below 35% of your maximum health, gain a shield for 65% of your maximum health for 5.5 seconds, during which you also gain 150% bonus movement speed and have reduced size (75 second cooldown). The shield and bonus movement speed decay over the duration. |
| **Mighty Shield** | Silver | Gain 40-100 adaptive force for 3 seconds upon gaining a shield (5 second cooldown). |
| **Mind to Matter** | Silver | Grants bonus health equal to 50% maximum mana. |
| **Swift and Safe** | Silver | After dashing or blinking, gain a shield that lasts for 2 seconds and absorbs 65-290 (+ 65% AD) (+ 26% AP) damage (5 second cooldown). |
| **Veil of Warding** | Silver | Grants a spell shield that blocks the next hostile ability (30 second cooldown, timer does not restart from champion damage taken). |
| **Big Brain** | Gold | Gain a shield that absorbs damage equal to 300% AP and lasts until destroyed. Shield is replenished upon respawn and every 70 seconds. |
| **Celestial Body** | Gold | Gain 1500 bonus health, but reduce your damage output by 10%. |
| **Dawnbringer's Resolve** | Gold | Upon dropping below 50% maximum health, you are healed for 30% of your maximum health over 3 seconds (45 second cooldown, reset upon death). |
| **Outlaw's Grit** | Gold | Dashing or blinking grants 12 bonus armor and bonus magic resistance for 15 seconds, stacking up to 5 times for a total of 60 bonus resistances, and refreshing on subsequent triggers. |
| **Perseverance** | Gold | Grants 1000% base health regeneration, increased to 2000% while below 25% maximum health. *[disabled in live (wiki)]* |
| **Porcupine** | Gold | Store up to 400-3900 pre-mitigation damage taken from champions; when full, burst needles in 400 radius for 75-200 (+125% bonus armor) (+125% bonus MR) physical and 30% slow for 2 s. |
| **Shrink Ray** | Gold | Basic attacks on-hit reduce the target's damage dealt by 15% for 3 seconds, refreshing with each hit. Their size is also reduced significantly for the duration. |
| **Vampirism** | Gold | You can no longer be healed by allies and your health regeneration is set to 0. Gain 25% omnivamp. *[disabled in live (wiki)]* |
| **Courage of the Colossus** | Prismatic | Immobilizing or grounding an enemy champion grants a shield for 3 seconds that absorbs 150-450 (+ 4% maximum health) damage (5 second cooldown per cast instance). Shields can stack between multiple triggers of this effect, though not refreshing the duration of previous shields. |
| **Giant Slayer** | Prismatic | Become tiny: -75% size and +20% bonus MS. Deal 10% / 15% / 25% / 30% bonus damage to champions bigger than you (tiers by size difference). |
| **Goliath** | Prismatic | Grants 35% bonus health, 15% adaptive force, and 50% increased size. |
| **Mad Scientist** | Prismatic | Upon acquiring this augment and each time you respawn, gain either 30% adaptive force, 20% bonus health, and 40% increased size or 70 ability haste, 40% bonus movement speed, and 40% reduced size. |
| **Squishy Slappy Grab** | Prismatic | When an enemy is within 450, after 1.5 s tether all enemy champions within 800 for 4 s (30 s CD). Your next attack yanks them toward you (450 units): 50-150 (+15% bonus HP) magic, 0.25 s stun, and you gain a 50-200 (+50% bonus armor) (+50% bonus MR) shield per enemy pulled (2.5 s). |

### 2.7 Healing, shielding & team support (13: 2S / 7G / 4P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Sonic Boom** | Silver | Granting a buff, heal, or shield to your ally deals 30-150 true damage to enemies within 450 units of them and slows targets by 30% for 2 seconds (2 second cooldown). |
| **Support Main** | Silver | QUEST: heal allied champions for 3,000 total. REWARD: every heal you give also adds a heal-over-time worth 25% of the initial heal over 3 s. (Client data: HealPercent 25, HealDuration 3, quest milestone 3000.) |
| **All For You** | Gold | Your heals and shields on allied champions are increased in effectiveness by 30%. |
| **Critical Healing** | Gold | Your heals and shields now have a chance equal to your critical strike chance to increase in effectiveness by 40% (5 second cooldown per cast instance). Additionally, gain 25% critical strike chance. |
| **Nature is Healing** | Gold | Upon entering a patch of brush, you are healed for 40-300 (+ 15% of your missing health) over 1.5 seconds (20 second cooldown per brush patch). |
| **Our Healing** | Gold | Whenever a nearby unit is healed (excluding yourself), you heal yourself equal to 15% of the amount they healed, doubled to 30% from the heals of enemies. *[slated for removal in 26.21 (PBE)]* |
| **Pat On The Back** | Gold | Whenever you are within 200 units of an allied champion, they pat you on the back, granting you a 50-150 (+ 25% bonus movement speed) shield and 30% bonus movement speed for 3 seconds (9 second cooldown). Subsequent passes only refresh the duration of the effects. |
| **Searing Dawn** | Gold | Gain Sunlight. Sunlight: Your damaging abilities mark enemies, causing them to take 40-200 bonus magic damage from your ally's next basic attack or ability hit against them (0.75-second cooldown per target). |
| **Wee Woo Wee Woo** | Gold | Gain 0-50% bonus MS while facing nearby allies (more the more HP that ally is missing; lingers 2 s). Your heals/shields on them are 0-50% stronger on the same scale. |
| **Circle of Death** | Prismatic | Healing and health regeneration you do causes you to deal 70% of that value in magic damage to the nearest enemy champion within 1000 units. |
| **Empowered By The Faithful** | Prismatic | Your heals/shields 'bless' allies for 8 s; each champion hit a blessed ally lands gives you Devotion (max 50). At 50: shockwave around you for 50-300 (+750% heal & shield power) magic that executes champions below (25% x your heal & shield power) of max HP. |
| **Spirit Bomb** | Prismatic | Your healing + shielding (self or allies) charges a Spirit Bomb; after 200-2000 total it is thrown at the most wounded ally: 475-radius heal 5-15% (+3% per 100 AP) missing HP and 2 s shield 10-25% (+2% per 100 AP) current HP. |
| **Windspeaker's Blessing** | Prismatic | Your or allies' heals and shields on yourself, or your heals and shields on allies, grant the target 30-60 bonus armor and bonus magic resistance for 3 seconds. |

### 2.8 Mobility, tempo & assassination (11: 4S / 3G / 4P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Homeguard** | Silver | Gain 100% bonus movement speed. This bonus is lost for 6 seconds after taking damage. |
| **Kill Secured** | Silver | Gain 60% bonus movement speed towards enemy champions below 40% of their maximum health. |
| **Leg Day** | Silver | Gain 50 bonus movement speed and 50% slow resist. |
| **Shadow Runner** | Silver | After dashing, blinking, or exiting stealth, gain 300 bonus movement speed for 2 seconds. |
| **Get Excited!** | Gold | Scoring a champion takedown grants you 100% bonus movement speed and 15% total attack speed for 4 seconds. |
| **Nightstalking** | Gold | Scoring a takedown against an enemy champion within 3 seconds of damaging them renders you invisible for 1.5 seconds, during which you also gain 40% bonus movement speed. Attacking or casting abilities ends the stealth immediately. |
| **With Haste** | Gold | Grants bonus movement speed equal to 70% ability haste. |
| **Earthwake** | Prismatic | Dashes/blinks leave a trail that detonates after 0.75 s (300 radius) for 90-250 (+125% bonus AD) (+60% AP) physical (70% vs minions; each enemy hit max once per second). Offered to max 2 players per team. |
| **En Passant** | Prismatic | See a directional 'Vital' arc on enemy champions within 2000. Hitting a champion while facing their exposed Vital: 6% (+1.5% per stack) max HP true damage, heal 50-200 (+5% missing HP), 50% (+5%/stack) decaying MS, +1 stack (8 s). A new Vital appears in a different direction 4 s later. |
| **Goldrend** | Prismatic | Damaging basic attacks or abilities against enemy champions deal 50-150 (+ 40% bonus AD) (+ 20% AP) bonus magic damage, and grant you 30 and 25% bonus movement speed for 1.5 seconds (30 second cooldown per champion). |
| **Rite of Ascension** | Prismatic | Takedowns within 3 s of damaging the champion leave an Essence (8 s). Attack it from within 400: 1.25 s untargetable windup, blink to it, heal 75-300 (+50% bAD) (+25% AP) (up to x2 by missing HP), +100% decaying MS, reset basic ability cooldowns. |

### 2.9 Auto-cast 'free extra ability' augments (9: 1S / 4G / 4P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **FireFox** | Silver | Auto-cast Ahri's Fox-Fire (7 s CD): 25% decaying MS; 3 flames orbit you then seek the nearest enemies within 550 for 35-160 (+25% bAD) (+25% AP) adaptive each (30% for extra flames on the same target). |
| **Divine Intervention** | Gold | Automatically cast Cosmic Radiance, calling down a protective star upon you that descends over 2.5 seconds. Afterwards, you and all allied champions within cr 400 units become invulnerable for 2.5 seconds (35 second cooldown). |
| **Endless Decimation** | Gold | In combat, auto-cast an improved Darius Q (8 s CD): 1.25 s windup, 460 radius, 100-400 (+60% AD) (+40% AP) physical (inner 240 radius takes 50%). Each champion hit by the blade heals you 18% missing HP and cuts the CD by 10% (min 3 s). |
| **Ok Boomerang** | Gold | Automatically cast an improved version of Boomerang Blade at the closest nearby enemy champion within 1250 units, dealing 40-200 (+ 30% bonus AD) (+ 20% AP) adaptive damage to enemies hit (10 second cooldown). |
| **Sonata** | Gold | Alternating auto-casts every 10 s: Aria (heal self and the most wounded ally within 1000 for 60 (+60% AP); aura shield 80 (+40% AP) for 1.5 s) then Celerity (self +30% MS for 7 s; aura gives allies +20% MS 3 s). |
| **Devil on Your Shoulder** | Prismatic | Pact with Little Devil Teemo: lose 0.5% current HP/s (5%/s when enemy champions within 1000). In return deal +20% bonus true damage, and your hits spawn Life Remnants (pick up: heal 50-150 (+50% bAD) (+25% AP), +15% MS). *[disabled in live (wiki)]* |
| **Prom Queen** | Prismatic | Auto-cast Rakan's The Quickness (35 s CD; tiara appears 2.5 s before): 6 s sprint with ghosting and +50% MS; enemies you touch are knocked down and charmed for 1.5 s. |
| **Quantum Computing** | Prismatic | Auto-cast Camille-style Tactical Sweep when an enemy champion is within 650 (30 s CD): 0.75 s windup, 200-350 (+75% bAD) (+45% AP) physical in 650 radius; enemies on the outer edge take +10% max HP bonus (plus scalings), are slowed 80% (decaying 2 s) and heal you for 80% of that bonus damage. *[disabled in live (wiki)]* |
| **Triggered Inferno** | Prismatic | Hitting a different champion than your previous hit gives Style (6 s, max 7; +4.25-5% MS each). At 7 Style: a 2 s Samira-style torrent - shoot enemies within 600 every 0.2 s (max 10 shots per enemy) for 20-40 (+40% AD) (+25% AP) physical (25% vs minions); targets under 30% HP take double. 5 s CD. Applies life steal. |

### 2.10 Ability Augments (upgrade ONE of your champion's abilities) (31: 8S / 17G / 6P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Adaptive Ward** | Silver | Ability augment: when the chosen ability hits a champion gain 7-12 bonus armor (vs physical targets) or MR (vs magic targets) for 6 s (4 s CD), stacking a few times. |
| **Bolstered** | Silver | Ability augment (shield ability): that ability's shield is 0-60% stronger, scaling with the target's missing HP. |
| **Double Strike** | Silver | Upgrades one of your champion's abilities that has an empowered basic attack effect, further enhancing the attack to apply on-hit effects to targets it hits a second time. *[disabled in live (wiki)]* |
| **It's Go Time** | Silver | Upgrades one of your champion's abilities that has a duration-based effect, empowering the ability to grant 25-45 bonus movement speed for the effect's duration. |
| **Siphon** | Silver | Upgrades one of your champion's abilities, empowering the ability to heal you for 30% of its post-mitigation damage dealt to enemy champions. |
| **Spin To Win** | Silver | Your spinning abilities deal 30% increased damage and have their cooldown reduced equivalent to 30 ability haste. The damage amplifier is increased to 50% for ultimate abilities. |
| **Stay Resolute** | Silver | Ability augment: when the chosen ability damages a champion, permanently gain 1-3 armor (vs physical targets) or MR (vs magic targets), infinite stacking, 5 s CD per target. If not your first augment: +20 armor and MR immediately. |
| **Trusty Weapon** | Silver | Upgrades one of your champion's abilities, empowering the ability to generate a Friendship stack for 6 seconds when it hits an enemy champion. For each Friendship stack you have, the ability deals 5% increased damage. This effect can stack up to a number of times. |
| **BONK!** | Gold | Upgrades one of your champion's abilities that has an empowered basic attack effect, further enhancing the attack to deal 30% increased damage to the target and 30% of its damage to nearby enemies. *[wiki lists Silver]* |
| **Bread And Butter** | Gold | Your champion's first basic ability (Q) gains 100 ability haste. |
| **Bread And Jam** | Gold | Your champion's second basic ability (W) gains 100 ability haste. |
| **Bread and Cheese** | Gold | Your champion's third basic ability (E) gains 100 ability haste. |
| **Chain Reaction** | Gold | Ability augment (knockback ability): a knocked-back champion that collides with another enemy champion -> both knocked up 0.5 s and the hit one takes 100-400 magic; collides with terrain -> rebounds for 150-800 magic, 0.75 s knock-up + 0.5 s stun (knock-up up to 1.1 s on long-CD abilities). Ultimates deal 250% damage. |
| **Lil' Extra Help** | Gold | Upgrades one of your champion's abilities that has an effect which empowers your basic attacks for a duration, further enhancing the attacks by granting you 150 (melee) / 100 (ranged) bonus attack range and 75% (melee) / 40% (ranged) bonus attack speed while the effect is active. |
| **Mercy's Strike** | Gold | Ability augment: casting the chosen ability empowers your next attack: +300 range, +75% AS, bonus magic damage = 3% (+2% per 10% heal & shield power) of target max HP (2.5% vs turrets). |
| **Pursuit of Haste** | Gold | Ability augment + quest on one ability: hit champions with it 10 times -> +80 ability haste on that ability; 30 total hits -> another +80 (160 total). |
| **Pursuit of Power** | Gold | Quest: Hit an enemy champion with a specific ability 10 times (counts up to 1 hit per champion per cast instance). Reward: Upon completing your Quest, increase the damage of the ability by 30%. |
| **Quickstep** | Gold | Upgrades one of your champion's abilities, empowering the ability's cast to cause you to dash up to 350 units towards your cursor. |
| **Ravenous Bind** | Gold | Upgrades one of your champion's abilities that has a immobilizing or grounding effect, empowering the ability to deal 15-90 (+ 10% AP) (+ 0.5% of your maximum health) magic damage to affected targets and heal you for 50-200 (+ 5% AP) (+ 10% bonus health). The heal is increased by up to 50% based on how long the ability's cooldown is. |
| **Rejuvenation** | Gold | Ability augment: casting the chosen ability heals you for 30-100 (+25% bonus AD) (+15% AP) (+5% bonus HP), up to +50% more on long-cooldown abilities. |
| **Reload** | Gold | Upgrades one of your champion's abilities that has a duration-based effect, causing basic attacks on-hit during the ability to reduce its remaining cooldown by 0.15-0.35 seconds. *[disabled in live (wiki)]* |
| **Snap Back** | Gold | Upgrades one of your champion's abilities, empowering the ability with a recast. Using the recast causes you to blink back to your original casting position of the ability and explode to deal 100-300 (+ 20% AD) (+ 20% AP) magic damage to nearby enemies. *[disabled in live (wiki)]* |
| **Terrain'd** | Gold | Ability augment (terrain-creating ability, e.g. Anivia W, Azir R, Trundle E): the terrain deals 20-180 (+20% AP) magic to nearby enemies; x3 (+200%) if the ability is an ultimate. |
| **Terror** | Gold | Upgrades one of your champion's abilities, empowering the ability's cast to fear all enemies within 450 units of you for 1.75 seconds (30 second cooldown). *[wiki lists Silver]* |
| **Void Dash** | Gold | Upgrades one of your champion's abilities that has a dash, empowering the ability to spawn a void zone (250 radius) at the dash's destination after a 0.3-second delay. Enemy champions within the zone are dealt 80-400 (+ 100% ability haste) magic damage and are slowed by 35% for 1 second. *[disabled in live (wiki)]* |
| **Echo Cast** | Prismatic | Upgrades one of your champion's abilities, empowering the ability's cast to summon a clone of your champion that is untargetable and moves up to 500 units towards your cursor. The clone then casts the ability it was summoned from after a 0.25-second delay, mimicking the active effects of the casted spell and disappearing after it finishes casting. |
| **Multishot** | Prismatic | Ability augment + quest: hit champions with the chosen missile ability. 6 quest tiers (hit counts 50, 250, 700, 2000, 4000, 8000 divided by the ability's base CD) each add +1 missile, fired in a cone (up to 7). Repeat hits on the same target deal 30%. |
| **Overloaded** | Prismatic | Upgrades one of your champion's abilities, empowering the ability to have its cooldown reset whenever you cast a different ability. |
| **Pin Cushion** | Prismatic | Ability augment (duration ability): basic attacks during it stick Nails on champions; when it ends (or you die) each Nail deals 20-60 physical (instantly if lethal) and gives you +10 MS per Nail for 3 s. |
| **Spell Split** | Prismatic | Ability augment (missile): the missile splits into two perpendicular missiles at max range or when recast (after 0.15 s); split missiles apply full effects, repeat hits on the same target deal 30%. |
| **Tripleshot** | Prismatic | Upgrades one of your champion's abilities that is unit-targeted and fires a missile, empowering the ability to fire its missiles at two additional enemies near the primary target. Subsequent hits from the same cast against the same enemy deal 30% damage. |

### 2.11 Snowball (Mark/Dash) upgrades (7: 1S / 4G / 2P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Snowday** | Silver | Your Mark deals 100% increased damage and has its cooldown reduced equivalent to 100 ability haste. (Grants Mark if not equipped.) |
| **Pinball** | Gold | Mark becomes a pinball: 100-500 bonus true damage; it ricochets off terrain up to 4 times, each bounce resetting range, +25% radius, +20% damage and -30% remaining Mark CD (max +100% radius / +80% damage). Mark CD reduced by 50 haste-equivalent. |
| **Shark Tempest** | Gold | Mark circles sharks around the snowball (300 radius): 100-200 magic + 40% slow 1 s along its path. On champion hit the sharks circle the target (425 radius) for 3 s: 30-90 (+25% bAD) (+15% AP) magic per second + 40% slow. |
| **Snowball Upgrade** | Gold | Mark hit creates a 2 s snowstorm at the target: 200 (+200% bonus AD) (+120% AP) magic damage over the duration (ticks every 0.25 s), 50% (+6% per 100 AP) slow, grants vision. Mark CD reduced by 50 haste-equivalent. Grants Mark if needed. *[disabled in live (wiki)]* |
| **Snowblast** | Gold | Empowers the Dash spell from Mark to deal 100% increased damage and upon arrival cause you to knock up the target for 0.5 seconds and knock back nearby enemies. Additionally, your Mark cooldown is reduced equivalent to 100 ability haste. (Grants Mark if not equipped.) |
| **Biggest Snowball Ever** | Prismatic | Mark becomes a giant snowball that passes through non-champions; on champion hit it explodes for 200-350 (+100% bonus AD) (+60% AP) magic AoE, knock-up 0.75 s, 20% slow 2 s (non-champions hit are stunned 1.25 s). Mark CD reduced by 100 haste-equivalent. |
| **Holy Snowball** | Prismatic | After using the Dash spell from Mark, you become invulnerable for 1.5 seconds upon arrival. Additionally, your Mark cooldown is reduced equivalent to 100 ability haste. (Grants Mark if not equipped.) |

### 2.12 Death, revive & on-death payoffs (4: 1S / 1G / 2P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Dive Bomber** | Silver | Upon death, you explode to deal true damage equal to 20% of the target's maximum health to enemies within 500 units. |
| **Shark Bait** | Gold | On fatal damage you become Shark Bait for 3.5 s: zombie state (static 400 MS, ghosted, invulnerable, CC-immune, cannot attack/cast; enemies within 400 slowed 40%). Then a giant shark chomps (400 radius) for 120-350 (+30% of target's missing HP) magic and 1 s knock-up. |
| **DropBear** | Prismatic | On death Tibbers drops onto your corpse: 250-750 (+100% AP) magic AoE + 1.5 s stun, then hunts your killer for 8-20 s (copies your other augments, burns 25-150 (+50% AP) magic/s around him, 50 armor/MR). *[slated for removal in 26.21 (PBE)]* |
| **Hellbent** | Prismatic | Hitting champions builds Revivemaxxing (6 s, max 10). At max you are Hellbent: on lethal damage, 4 s invulnerable resurrection, revive with 35-75% max HP (90 s CD), then 15 s empowered: +15-120 bonus AD or 25-200 AP, +20-40 MS toward enemies, 15-30% omnivamp. |

### 2.13 Summoner-spell replacers & transformations (11: 4S / 2G / 5P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Flash 2** | Silver | Replace a summoner spell with Flash. Additionally, gain 70 summoner spell haste. |
| **Flashbang** | Silver | Using Flash creates an explosion around the blink location that deals 70-240 (+ 70% AD) (+ 60% AP) magic damage to nearby enemies and slows them by 35% for 1.25 seconds. Additionally, the cooldown of your Flash resets upon your death. (Grants Flash if not equipped.) |
| **Poltergeist** | Silver | Replaces a summoner spell with Poltergeist (68 s CD): casts Barrier (shield ~110-440 by level) AND Ghost (30% bonus MS + ghosting) together for 5 s. |
| **Spin Me Right Round** | Silver | Replaces a summoner spell with Akshan's Heroic Swing (10 s CD): hook a wall, swing around it shooting the nearest enemy every 0.2 s for 15-75 (+15% AD) physical (x(1 + 0.3 per 100% bonus AS); on-hit at 25%), then recast to leap off with a final shot. Gives a 400 minimum attack range for the shots. |
| **Flashy** | Gold | Your Flash now has 3 charges with a 2-second cooldown between casts (120 seconds recharge time for all 3 charges). (Grants Flash if not equipped.) |
| **Growth Spurt** | Gold | Replaces a summoner spell with Growth Spurt (76.5 s CD): instantly grow +50% size, knock up/back enemies within 400 (1 s, 275 units) and gain +300 bonus max HP (base value; scales) for 7 s. |
| **Blade Waltz** | Prismatic | Replaces a summoner spell (45 s CD): blink to an enemy champion, then blink to the nearest other enemy champion every 0.25 s for 1.75 s (up to 7 more blinks; last one returns to the primary target). Each blink: 30-150 (+10% bonus AD) (+6% AP) physical and on-hits at 50%. Untargetable and unable to act during it. |
| **Clown College** | Prismatic | Gain Shaco pieces: Backstab passive (attacks from behind +20-35 (+50% bAD) (+35% AP) physical); Deceive replaces a summoner spell (45 s CD: 3 s stealth + 400-unit blink, next attack +100 (+150% bAD) (+55% AP), x1.55 with Backstab); on death explode for 25% max HP true damage in 350 radius and drop a Jack-in-the-Box that fears 1 s. |
| **Dimension Shift** | Prismatic | Replaces a summoner spell with When the Darkness Comes (180 s CD): a light lands (500 radius) and every unit inside is sent to a separate Dark Realm for 8 s; you gain bonus HP/AP/AD/size there. Units in different realms can't interact; champions in the realm deal only 1 damage per hit to structures. *[slated for removal in 26.21 (PBE)]* |
| **Empyrean Promise** | Prismatic | Replaces a summoner spell with Vigilance (20 s CD, 2000 range): after 0.25 s dash to an allied champion; both of you get a 100-250 (+100% AP) (+10% bonus HP) shield for 3 s. Also +15% heal & shield power. |
| **Poro Stampede** | Prismatic | Poro-Snax spawn near you every 25-15 s (max 2). Feeding Poros = Poro Love; at 5 you get the Poro Charge summoner (120 s CD): waves of Poros dealing 100-200 (+20 per Poro Love) physical; first wave slows 85% for 2 s; 15% dmg to minions, 50% on repeat waves. Quest tiers at 12/20/30/44/63/90/129/187/275 Poro Love each add a wave. *[slated for removal in 26.21 (PBE)]* |

### 2.14 Keystone-rune packs (3: 0S / 2G / 1P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **From Beginning To End** | Gold | Gain the Dark Harvest and First Strike keystone runes. |
| **Impassable** | Gold | Gain the Aftershock and Glacial Augment keystone runes. |
| **Symphony of War** | Prismatic | Gain the Conqueror and Lethal Tempo keystone runes. |

### 2.15 Item upgrades & item quests (16: 4S / 6G / 6P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Upgrade Collector** | Silver | Upgrades The Collector, empowering Death to have its execution threshold increased by 0.5% each time you kill an enemy champion, capped at a threshold of 12.5% of the target's maximum health, and Taxes to generate a further 25 (total 50) from kills. Additionally, gain 250. |
| **Upgrade Death's Dance** | Silver | Upgrades Death's Dance, empowering Ignore Pain with an increased damage reduction of 40% (melee) / 15% (ranged) and Defy with an increased heal AD ratio of 125% bonus AD. Defy's healing is also granted instantly upon the passive effect being triggered rather than over 2 seconds. Additionally, gain 250. |
| **Upgrade Immolate** | Silver | Upgrades Bami's Cinder, Hollow Radiance, Sunfire Aegis, and Void Immolation, empowering Immolate to additionally grant you 12 per tick for each enemy champion afflicted by its effect. Additionally, gain 250. |
| **Upgrade Zhonya's** | Silver | Upgrades Seeker's Armguard, Wooglet's Witchcap, and Zhonya's Hourglass, empowering Stasis to cleanse you of all crowd control and allow you to move during its active effect, during which time you also gain 50% bonus movement speed. Additionally, the cooldown of Zhonya's Hourglass Stasis is reduced to 45 seconds. |
| **From Downtown** | Gold | QUEST: land 15 ability hits on champions from 600+ units. REWARD: such hits call down a meteor (8 s CD per target/cast) for 75-200 (+50% bAD) (+20% AP) magic; damage grows up to x2.3 and radius from 150 up to ~1,700 units with distance. |
| **Steel Your Heart** | Gold | QUEST: own Heartsteel and gain 300 bonus HP from its Colossal Consumption stacks. REWARD: Colossal Consumption grants +200% bonus HP from then on. |
| **Upgrade Infinity Edge** | Gold | Upgrades Infinity Edge, empowering it to gain Sword of the Divine Excoriate. Additionally, gain 500. Excoriate: Gain a random amount of bonus critical strike damage that scales up to 50% of your critical strike chance, with the value of this amount changing every 0.25 seconds. |
| **Upgrade Ravenous Hydra** | Gold | Upgrades Ravenous Hydra, increasing its life steal stat to 20% and empowering Cleave to trigger its effect on ability hits against enemies (1 second cooldown per ability). Additionally, gain 500. |
| **Upgrade Sheen** | Gold | Upgrades all Spellblade items, empowering the passive effect to deal additional bonus physical damage equal to 4% of the target's maximum health and heal you for 3.5% of the target's maximum health. Additionally, gain 250. |
| **Upgrade Sundered Sky** | Gold | Upgrades Sundered Sky, empowering Lightshield Strike with an increased heal health ratio of 9% of your missing health and a reduced cooldown of 5 seconds. Additionally, gain 500. |
| **Icathia's Fall** | Prismatic | Gain Bami's Cinder; you may buy Hollow Radiance and Sunfire Aegis despite the Immolate limit. QUEST: own both -> they fuse into Void Immolation (1000 HP, 100 armor, 80 MR, 25 AH, 5 s Immolate, Desolate on-kill blast). |
| **Sneakerhead** | Prismatic | Each boots item is given to you in turn with a mini-quest (Berserker's: 25 attacks; Swiftness: 300 steps; Lucidity: 20 casts; Mercury's: be CC'd 5 times; Steelcaps: block 200 dmg; Sorcerer's: 1500 ability dmg). Finish all six -> Jarvan I's (super boots). You cannot buy boots. *[disabled in live (wiki)]* |
| **Ultra Hydra** | Prismatic | Buy Tiamat, Profane, Ravenous and Titanic Hydra despite the Hydra limit; each Legendary Hydra (not Stridebreaker) gives a free Tiamat. QUEST: own Profane + Ravenous + Titanic -> they fuse into Ultra Hydra (6000-gold value: 200 AD, 25 AH, 25 lethality, 1000 HP, 15% omnivamp, giant cleave active). Hydras can't be sold. |
| **Upgrade Sword of Blossoming Dawn** | Prismatic | Upgrades Sword of Blossoming Dawn, empowering Peppermint to have its healing increased by 250%. Additionally, you gain 100% bonus attack speed. |
| **Urf's Champion** | Prismatic | QUEST: score 18 champion takedowns. REWARD: The Golden Spatula (90 AD, 110 AP, 40% AS, 15% crit, 200 HP, 20 armor/MR, 200 mana, 20 AH, 10% MS, 10% life steal, regen, burn aura). |
| **Wooglet's Witchcap** | Prismatic | Gain a Needlessly Large Rod. QUEST: own Rabadon's Deathcap + Zhonya's Hourglass -> they fuse into Wooglet's Witchcap (300 AP, 50 armor, 20 AH, +50% total AP, Stasis on a 60 s CD in Mayhem). |

### 2.16 Economy, RNG & meta-augments (11: 2S / 4G / 5P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Stats!** | Silver | Gain 2 Stat Bonus. |
| **Transmute: Gold** | Silver | Gain one random Gold-tier augment. |
| **Donation** | Gold | Gain 1750 upon acquiring this augment. |
| **Stats on Stats!** | Gold | Gain 3 Stat Bonus, with a higher chance of obtaining Gold- and Prismatic-tier anvils. |
| **Transmute: Prismatic** | Gold | Gain one random Prismatic-tier augment. |
| **Yowch, My Coins!** | Gold | Enemy champions that you score a takedown against drop 6-10 coins, with each coin landing 500 units away from the location of their death and lasting 10 seconds. You or allied champions can collect the coins by moving over them, granting 15 for each coin collected. *[slated for removal in 26.21 (PBE)]* |
| **High Roller** | Prismatic | Nearby enemies that die have a 0.5% chance to drop a Stat Bonus at the location of their death, reduced to a 0.25% chance for non-champions. You can pick up dropped anvils by moving over them. The obtained Stat Bonus will be consumed once the shop is enabled again (after your death). *[slated for removal in 26.21 (PBE)]* |
| **King Me** | Prismatic | The first time you enter the enemy team's gate/Catapult (next to their spawn) you are 'Kinged': gain one random Prismatic augment, and your first eligible Legendary item gets +1000 gold worth of its own stats. |
| **Pandora's Box** | Prismatic | Gain a random Prismatic augment AND every augment you already own is re-rolled into a random Prismatic augment. |
| **Stats on Stats on Stats!** | Prismatic | Gain 4 Stat Bonus, with a higher chance of obtaining Gold- and Prismatic-tier anvils. Additionally, on the next round of augment selection, you gain an additional reroll per augment slot. |
| **Transmute: Chaos** | Prismatic | Gain TWO completely random augments of any tier (never the other two currently offered). |

### 2.17 Dragon souls, map & minions (8: 4S / 2G / 2P)

| Augment | Tier | Effect (live 26.20) |
|---|---|---|
| **Hextech Soul** | Silver | Grants the Hextech Dragon Soul, or a different Dragon Soul if you already have it. |
| **Infernal Soul** | Silver | Grants the Infernal Dragon Soul, or a different Dragon Soul if you already have it. |
| **Mountain Soul** | Silver | Grants the Mountain Dragon Soul (periodic shield when out of combat), or a different Dragon Soul if you already have it. |
| **Ocean Soul** | Silver | Grants the Ocean Dragon Soul, which has a modified base heal value of 100, or a different Dragon Soul if you already have it. |
| **Minionmancer** | Gold | Your pets deal 40% increased damage as well as gain 40% bonus health and size. |
| **Overextender** | Gold | Butcher's Bridge only: Cannon Launcher range +12,000 (18,500 total), impact damage +50% (180-690 magic), much faster flight; your Recall is enabled and upgraded to Empowered Recall. |
| **Hand of Baron** | Prismatic | Gain a modified Hand of Baron, which only grants 25% increased adaptive force and greatly empowers nearby allied minions. |
| **Omni Soul** | Prismatic | Grants 3 random Dragon Soul. |

### 2.18 Removed/legacy augments worth stealing (launch → 26.11)

These no longer exist in the live client, but several were the mode's most famous memes and make good optional content. Text comes from older revisions of the wiki data module (Jan and May 2026; [wiki data][W-AugData]).

| Augment (old tier) | Effect |
|---|---|
| **Final City Transit** (G) | On death, a train spawns near your killer and charges across the map at them: 150–750 (+65% bAD) (+50% AP) (+15% max HP) physical to everything it passes through |
| **Poro Blaster** (G) | Summon a Poro every 3.5 s (max 5). Damaging a champion launches all Poros, each for **3% max HP true damage**; the first knocks up 0.5 s if you had 5. Max 1 per team. Notorious for being overtuned and buggy ([Reddit/Riot Cadmus][Reddit-Cadmus]) |
| **Hat on a Hat** (S) | +15 AP and +8 MR per hat or headwear item you own (Rabadon's, Liandry's…); +8 AP / +4 MR for Cappa Juice and anvil hats |
| **I'm a Baby Kitty Where is Mama** (P) | Tether to the nearest ally: +75% MS and +50% heal & shield power while tethered, +37.5% MS when facing them. A Yuumi fantasy for anyone |
| **Grandma's Chili Oil** (G) | Your next hit Burns for 100–350 over 3 s and throws a chili canister. It leaves a 175-radius oil pool for 5 s that heals allies 30–75/s and burns enemies 150/s |
| **Heads Up Cupcake!** (P) | Cupcakes fly across the map. Touching one heals the eater and nearby allies 50–250 (+5–15% missing HP) and gives 50 g; you earn 150 g per 1,000 cupcake healing |
| **Bounce of the Poro King** (P) | Summoner spell: become the Poro King and bounce around (base 100–700 damage, 70% damage reduction, +40% MS) |
| **Droppybara** (P) | Summoner spell that drops a capybara from the sky; max 1 per team |
| **Orbital Laser** (P) | Summoner spell: after 2.5 s a laser deals 25% max HP true damage, then 60–100 magic every 0.5 s for 3 s in 550 radius; max 1 per team |
| **Trueshot Prodigy** (P) | Hitting an enemy from 700+ units casts Ezreal's Trueshot Barrage at them (100–350 (+80% bAD) (+60% AP), 15 s CD); max 1 per team |
| **Self Destruct** (S) | Every 25 s a bomb attached to you explodes after 5 s: 20% max HP true damage in 350 radius plus a 0.75 s knock-up |
| **Snowball Roulette** (G) | Mark hit casts a random harmful summoner spell on the target and a random beneficial one on you; Dash recasts the beneficial one |
| **Feel the Burn** (P) | Summoner spell: Exhaust (50% slow) and Ignite (70–410 true damage) on every enemy champion within 800 |
| **Laser Heal** (P) | Summoner spell: a beam that heals allies 150–430 and damages enemies 100–350 along its line |
| **Repulsor** (S) | Dropping below 35% HP knocks all enemies within 500 back 750 units and slows them 90% for 1.5 s (25 s CD) |
| **Slow and Steady** (G) | Attack speed locked at 0.625. Gain +25 AD, and every 1% bonus AS becomes +1 AD |
| **Speed Demon** (S) | Ability hits on champions give +200 decaying MS (nerfed from 350) |
| **Red Envelopes** (G) | Envelopes spawn near you every 25–15 s: gold, +100 MS and a random small permanent stat |
| **Gash** (P) | On-hit 20–40 (+25% bonus armor) true damage (halved for ranged) and +50% AS |
| **Void Rift** (P) | Ability hits leave Void Scars; two scars within 1,250 units connect into a rift for 100–450 magic damage and a 99% slow |
| **Executioner** (G) | +10% damage to targets below 30% HP; takedowns reset your basic abilities |
| **Cheating** (G) | Recall works and enables the shop; the platform heals you |
| **Twice Thrice** (G) | Every 3rd attack applies on-hit again at 150% |
| **Restless Restoration** (G) | Heal per distance travelled |
| **Rabble Rousing** (G) | Casting an ability heals 5–60 (+1% max HP). Later reworked into Rejuvenation |
| Others | Buff Buddies (permanent red/blue buffs), Crack Open That Egg (expiring shields explode), Demon's Dance / Keystone Conjurer / Cerberus (keystone pairs), Frost Wraith (auto Ring of Frost root), Holy Fire, Lightning Strikes, ReEnergize, The Brutalizer, Tormentor, Upgrade Hubris / Mikael's / Thornmail / Cutlass, Virtuous Cycle, Weighted Popoffs, Wind Beneath Blade, "???" (Enemy-Missing pings fire a missile that damages enemies and heals allies) |

### 2.19 Coming in 26.21 (PBE text; numbers not final)

From PBE client strings ([CommunityDragon PBE strings][CD-PBE]) and coverage ([arammayhem 4.0][AM-40], [GameRiv][GameRiv-2621]):

- **Get Jinxed!** (summoner-spell replacer): ride a rocket that explodes on hitting an enemy champion, structure or wall. It deals flat physical damage plus a % of **missing** HP, more the longer the ride.
- **Brass Blast** (summoner-spell replacer): charge a trumpet, then release it to knock back enemies and deal magic damage that scales with charge time.
- **BEES!!!**: periodically, your next ability hit on a champion launches an exploding beehive (bees slow and deal damage over time).
- **Totentanz** (summoner-spell replacer): blink forward and become unkillable for 5 s. Coverage disagrees on the failure case: either a takedown ends it early, or you must score a takedown (assists count) within 5 s or die. The client tracks "Deaths Defied / Lives Forfeited". Flavour: "You all die, why not choose how?" — Karthus.
- **Salvation**: dropping below 50% HP damages and knocks away nearby enemies and heals nearby allies.

---

## 3. Combos, synergies, fun and complaints

### 3.1 How augment math stacks (implementation notes)

- **Additive within a stat, multiplicative across layers.**
  - Flat AD/AP/AH/AS from augments add to item stats.
  - %-damage amplifiers multiply each other and multiply champion damage: Back To Basics +35% ability damage, Forged By The Master +45% item/augment damage, Hide on Bush +20%, Overflow +10%+, Celestial Body −10%.
  - Glass Cannon adds **true damage equal to 25% of pre-mitigation damage** (melee; 15% ranged). It ignores resists, so it scales with everything else.
- **Percent penetration stacks multiplicatively:** Thread the Needle 18% with a Prismatic pen shard 17.5% gives 1 − 0.82 × 0.825 ≈ 32.4%. Lethality and flat magic pen (Tooth Fairy, anvils) apply last ([armor pen][W-ArPen]).
- **Ability haste is additive but has diminishing returns:** CD × 100 / (100 + AH), capped at 500 AH (83%). Mayhem routinely reaches 150–300+ AH:
  - Recursion 60, Infinite Recursion 60 + 3 per takedown, Shrink Engine +8 per takedown, Eureka 30% of AP, Crit 'n Cast, Purist - Caster.
  - Per-spell haste: Bread 100 each, Dashing 175, Ultimate Awakening +300 for 15 s.
  - Ult Bot puts all haste on R at ×1.5 effectiveness.
- **Crit overflow:** crit chance above 100% becomes 0.45 AD or 0.75 AP per 1%. Many augments give +25% crit (Critical Rhythm, Critical Missile, Soul Siphon, Critical Healing, Twin Fire, Vulnerability, Tank It Or Leave It, Double Tap, Jeweled Gauntlet), plus It's Critical (+50%) and Zealot. "Crit everything" builds are a real archetype.
- **Attack-speed cap 5.0** in Mayhem (10 with Symphony of War's Lethal Tempo at max stacks).
- **Unbounded stackers are the snowball engines**, each with a death tax:
  - Tank Engine: +5% max HP and size per takedown; lose 65% of stacks on death.
  - Shrink Engine: +8 AH, +1% MS, −4% size per takedown; lose 65% on death.
  - Infinite Recursion: +3 AH per takedown.
  - Slap Around: +10 adaptive per immobilize; lose 50% on death.
  - Soul Eater: +20 HP per immobilize.
  - Stay Resolute: +1–3 armor or MR per hit.
  - Phenomenal Evil: +1 AP per ability hit.
  - Tooth Fairy: +3 lethality and magic pen per tooth.
  - Stackosaurus Rex doubles permanent stacks gained from abilities (Veigar, Nasus, Cho'Gath, Sion, Senna, Smolder…).

### 3.2 Known strong / beloved combos

| Combo | Why it works | Source |
|---|---|---|
| **Ethereal Weapon + Mystic Punch** | Abilities apply on-hit (1 s per target), and each on-hit cuts **all** ability CDs by 1.25 s. Spells refund each other in a loop | rated S together by [arammayhem][AM-Pris] |
| **Ethereal Weapon + on-hit stack** (Juiced, Heavy Hitter, Firebrand, Nashor's, BotRK, Guinsoo's, Kraken) | Turns spells into autos. Ezreal Q double-procs; Juiced + Muramana Ezreal procs three times | [arammayhem Ezreal][AM-Ez] |
| **Infernal Conduit + any Burn** (Firebrand, Pressure Cooker, Liandry's, Ignite, champion DoTs) | Every Burn tick refunds 0.08 s on all basic abilities, so cooldowns scale with how many enemies are burning. Brand is the poster child | [Elofactory][Elofactory], [arammayhem][AM-Pris] |
| **Jeweled Gauntlet + crit items/augments** (It's Critical, Zealot, Rite of Ruin, IE, crit-damage shard) | Abilities crit for 145% + bonus crit damage. Zealot scales crit with AP | [wiki][W-AugData], [arammayhem][AM-Pris] |
| **Bread ×3 ("Bread Sandwich")** | 100 AH on each of Q/W/E, then +50 more each and +250 ultimate haste | [wiki][W-Aug] |
| **Tank Engine + Goliath + Heartsteel + Steel Your Heart (+Celestial Body, Mind to Matter)** | Health snowball: every takedown is +5% HP and size, and Heartsteel stacks grow with size and HP. Pair with **Heavy Hitter** (3.5% max HP on every auto), **Dropkick** (explosion scales with bonus resists) or **Circle of Death** to turn bulk into damage | [wiki][W-AugData], [mobalytics builds][Moba-Builds] |
| **Shrink Engine + Giant Slayer (+Mad Scientist small form)** | Tiny, fast, huge ability haste. Giant Slayer deals up to +30% to anything bigger | [arammayhem][AM-Pris] |
| **Phenomenal Evil + Stackosaurus Rex** on stacking champions | Doubled permanent stacks give Veigar-style infinite scaling. "Veigar stacking AP" is one of the most cited fun moments | [Inven][Inven], [Riot dev blog 2][Riot-Dev2] |
| **Ult Bot / Ultimate Revolution + ultimate-triggered augments** (Can't Touch This, Final Form, Fey Magic, Stuck In Here With Me, It's Killing Time, Surge Field, Ultimate Awakening) | Ultimates every few seconds, each with an extra payload. Ultimate Revolution's reset also refreshes on death (Karthus/Fiddlesticks trick) | [arammayhem][AM-Pris] |
| **Back To Basics** on champions whose ultimate is passive or weak (Ryze, Rumble, Gangplank, Ezreal) | +35% ability damage, +70 AH and +35% healing/shielding for giving up an ult you barely use | [arammayhem][AM-Pris] |
| **Draw Your Sword + Dual Wield / Scopier Weapons** | Ranged carries become melee juggernauts with +24–100% AD/AS/HP/MS and 20% life steal. Bonus range from augments still applies | [wiki][W-AugData], [arammayhem Ezreal][AM-Ez] |
| **Purist - Caster on attack-speed casters** (Ezreal) | 0.65 AH per 1% bonus AS. With passive AS this can exceed 200 AH, giving a near-zero Q | [arammayhem Ezreal][AM-Ez] |
| **Multishot / Spell Split / Tripleshot / Echo Cast on hooks and binds** | A single Lux Q, Blitzcrank hook or Morgana bind catches the whole team; Riot used this as its headline example | [Riot dev blog 2][Riot-Dev2], [IBTimes][IBT-Hotfix] |
| **Chain Reaction on knockbacks** (Alistar, Poppy, Vayne E, Lee R, Malphite) | Knockbacks into walls or champions chain-stun and deal big damage (×2.5 on ultimates) | [Riot dev blog 2][Riot-Dev2] |
| **Snowball package** (Biggest Snowball Ever + Snowblast + Holy Snowball / Pinball / Shark Tempest) | Mark becomes an AoE engage on a CD that falls toward ~20 s. Holy Snowball adds 1.5 s of invulnerability on Dash | [wiki][W-AugData], [wiki Old content][W-Old] |
| **Healer engine** (Spirit Bomb, Support Main, All For You, First-Aid Kit, Protein Shake, Wee Woo, Empowered By The Faithful) | Heal & shield power stacks. Empowered By The Faithful's shockwave scales at **750%** of heal & shield power and executes. Circle of Death turns your own healing and regen into damage | [wiki][W-AugData] |
| **CC payoff kit** (Slap Around, Soul Eater, Cruelty, Courage of the Colossus, Ravenous Bind) on point-and-click CC champions | Each immobilize is a stack, a shield, a comet and a heal. Poro Blaster's poros once counted as CC, giving huge AP from one augment (bug) | [Reddit/Riot Cadmus][Reddit-Cadmus] |
| **"Suicide bomber"** (Dive Bomber + DropBear + Shark Bait + Clown College, formerly with the Dive Bomb set's −25% death timer) | Dying becomes a weapon: true-damage explosions, Tibbers drops and sharks | [arammayhem][AM-Pris], [wiki Old content][W-Old] |
| **Economy / variance plays** (Donation 1,750 g, Transmute: Prismatic, Pandora's Box, King Me, Transmute: Chaos) | Gambling for power spikes. King Me is a mid-game objective (reach the enemy gate) worth a Prismatic plus an item upgrade | [Riot dev blog][Riot-Dev1], [wiki][W-AugData] |

### 3.3 What makes Mayhem fun, according to Riot and players

- **Riot's design intent:**
  - "unlocking new, creative playstyles that still feel distinctly 'ARAM'"
  - "The combination of fast-paced teamfights with high-impact augments felt fresh"
  - Augments are "way bigger and wackier" than normal ARAM power spikes ([dev blog 1][Riot-Dev1]).
  - Mayhem is a **"champion-first"** mode: "Augments should serve to enhance the feel of playing your specific champion". "Many of Mayhem's most fun games are when your build starts to come together with a real identity". "we want each of your games to feel meaningfully different from the last". Balance is "a means to achieve a fun experience, rather than a strict state to maintain". "Strong builds shouldn't be the sole determinant in achieving victory" ([dev blog 2][Riot-Dev2]).
  - Riot prefers buffing weak augments, and removing or rotating unfair ones, over nerfing ([dev blog 2][Riot-Dev2]). After the 450-combination purge, Riot Cadmus said removed augments failed the mode's "high-roll, high-fun promise" ([IBTimes][IBT-Hotfix]).
- **Players:**
  - Short, explosive games (about 10–20 min) with a constant "dopamine" payoff.
  - Random augments rescue "doomed" random team comps and give a feeling of discovery.
  - Absurd moments such as Veigar's infinite AP or polymorph-Flash plays.
  - A tiny learning curve, since it's still ARAM ([Inven][Inven]).
  - "the most fun they've had in League in over a decade" ([Reddit thread][Reddit-Cadmus]).
  - The mode reportedly pulled about two-thirds of ARAM players into Mayhem ([Inven 2][Inven2]) and was made permanent.
- **Design read:** the fun comes from **(1)** a decision every few minutes, tied to dying; **(2)** shared-tier fairness, so everyone gets Prismatics at the same time; **(3)** augments that change verbs (new spell, melee conversion, revive, summoner spell) rather than only numbers; **(4)** visible, readable spectacle with persistent clutter cut; **(5)** snowball engines balanced by death penalties and Combo Breaker.

### 3.4 What players complain about

- **Variance:** high rolls feel stronger, low rolls weaker, and "bad augment combinations feel less playable" (top comment in the Riot Cadmus thread, [Reddit][Reddit-Cadmus]).
- **Dud augments that don't fit your champion:** the reason for the 26.12 filtering and the 450-combination purge ([IBTimes][IBT-Hotfix]).
- **Sets made builds samey** and put power behind traits ([dev blog 2][Riot-Dev2]).
- **Bugs and overtuned outliers:** Poro Blaster, Firecracker, Snowball double damage, infinite Pat On The Back shields ([Reddit][Reddit-Cadmus], [arammayhem 26.13][AM-2613]).
- **Tank balance swings:** "rarely picked → unkillable → one-shot" ([Reddit][Reddit-Cadmus]).
- **Visual clutter** and unclear tooltips. Riot cut persistent effects at launch and pledged clutter fixes ([dev blog 1][Riot-Dev1], [Reddit][Reddit-Cadmus]).
- **Progression-locked power** (the +300 starting gold reward) was disliked and removed ([Reddit][Reddit-Cadmus]).
- **Snowballing and one-sided games** when one team rolls Prismatic engines ([Inven 2][Inven2]).

---

## 4. Howling Abyss: layout facts for implementation

### 4.1 Structure list (per team)

Ordered from mid lane back to base ([wiki Howling Abyss][W-HA], [wiki Turret][W-Turret]):

1. **Outer turret** (1)
2. **Inhibitor turret** (1). There is **no "inner" turret on Howling Abyss**: each side has 4 turrets in total (1 outer, 1 inhibitor, 2 nexus).
3. **Inhibitor**
4. **Two nexus turrets**, flanking the approach to the nexus
5. **Nexus**
6. **Spawn platform / fountain** with the shopkeeper. There is no regen on the platform, and the shop range ends slightly past the nexus turrets.

Other features:
- **Frost-gate** in front of spawn: one-way travel from base towards mid. When your outer turret falls it moves up to in front of your inhibitor turret.
- **Base gates** keep champions in base for the first 15 s.
- **2 brush patches per side.**
- **4 health-relic pads** along the bottom wall: an "outer" relic near mid beyond each outer turret, and an "inner" relic between the outer and inhibitor turrets.
- The lane is about **1,700 units wide** (widened slightly in V12.23) ([wiki Lane via search][W-Lane]).

### 4.2 Geometry (estimate — no published coordinates found)

- The Mayhem client constrains the camera to x, y ∈ **[800, 12,500]** ([client][CD-Map12]), so the map is about a 12.8k × 12.8k square with the lane running diagonally from the blue base (bottom-left) to the red base (top-right).
- For a 1-D "lane axis" (0 = map centre, positive towards red), these spacings feel right and fit inside that square (fountain to fountain ≈ 14.5k units of the ~16.5k diagonal). **(estimate)**

| Object | Lane-axis position (units, mirror for blue) |
|---|---|
| Lane centre / mid | 0 |
| Outer health relic (bottom wall) | ±800 |
| Outer turret | ±1,650 |
| Inner health relic (bottom wall) | ±2,700 |
| Inhibitor turret | ±3,800 |
| Inhibitor | ±4,450 |
| Nexus turrets (2, offset ±300 across the lane) | ±5,050 |
| Nexus | ±5,600 |
| Shop-range edge | ±5,300 (just past the nexus turrets) |
| Spawn platform / fountain centre | ±6,800 to ±7,200 |

- **Tuning targets** (more useful than exact coordinates):
  - A 340-MS champion should walk spawn → mid in about **20 s**.
  - Turret range is **750**, and turrets should not overlap mid.
  - The outer turret should sit about **one screen** from mid.

### 4.3 Turrets (Howling Abyss values)

From the [wiki Turret page][W-Turret]:

| Turret | Health | Damage (scales with game minute) | Armor / MR | Range | Global gold / XP on kill |
|---|---|---|---|---|---|
| Outer | 1,300 + 250 per enemy champion | 185–293 | 60–81 | **750** | 150 g / 30 XP |
| Inhibitor | 3,900 + 250 per enemy champion | 205–385 | 63–84 | 750 | 150 g / 70 XP |
| Nexus | 1,800 + 250 per enemy champion. **Mayhem: base raised to 3,000** | 195–375 | 60–81 | 750 | 150 g / 120 XP |

- Attack speed **0.833** (one shot per 1.2 s). Outer-turret resists drop to 40 at 12:00.
- **Backdoor protection:** the inhibitor turret takes 35% less damage for 60 s after the outer turret falls (**Mayhem: 40% for 70 s**).
- **Champion damage ramp:** each consecutive shot on a champion +50%, up to +150%; resets 5 s after the last champion hit (the wiki labels this "Warming Up"; verify).
- Turrets take +20% damage from melee champions.
- **Reinforced Armor:** turrets take −80% damage (including true damage) when no enemy minions are nearby.
- **No turret plating** on Howling Abyss.
- **Targeting priority:**
  1. Pets
  2. Siege and super minions
  3. Melee minions
  4. Caster minions
  5. Champions

  It switches to an enemy champion that damages an allied champion within 1,400.
- Unmodified attacks on turrets deal 100% AD + 60% AP, as physical or magic, whichever is higher.

### 4.4 Inhibitor and nexus

- **Inhibitor:** 4,000 HP (client `bar_MaxHP 4000`), 20 armor, 15 HP/s regen, **respawns after 5:00** (general value; HA not listed separately) ([wiki Inhibitor][W-Inhib], [client][CD-Map12]).
- While an inhibitor is down, Mayhem spawns **1 super minion per wave** ([wiki][W-Mayhem]).
- **Nexus:** **3,000 HP in Mayhem** (ARAM 5,500) ([wiki][W-Mayhem]).

### 4.5 Health relics (Howling Abyss)

From the [wiki Health relic][W-Relic]:
- **Pickup:** the champion who grabs it is healed for 8% of missing HP and mana immediately.
- **Beam:** 2.5 s later, a heal of **16% missing HP and mana (Mayhem: 22%)** lands on every champion within **850** of the pad.
- **First spawn:** outer relics at **1:45**, inner relics at **2:30**.
- **Respawn:** **90 s** after the beam strikes. Timers are shown on the scoreboard.
- Champions only.

### 4.6 Minions

**Wave timing** ([wiki][W-ARAM], [wiki Minion][W-Minion], [client barracks][CD-Map12]):
- First wave at **0:50**, then every **25 s**. The wiki says the interval shrinks to 13 s between 18:00 and 30:00.
- Minions in a wave spawn **0.8 s** apart.

**Composition:** 3 melee + 3 caster, plus siege and super minions:
- **Siege:** client ARAM-family barracks use a [0,0,1] rotation (every 3rd wave) until **10:45**, then every 2nd wave until **25:00**, then every wave. The wiki says "every two waves, starting with the third". **(conflict)** Either is fine.
- **Super:** 1 per wave while an inhibitor is down (Mayhem).

**Movement speed:** 325 base, +10 every 60 s after 6:00, up to 12 times (client). The wiki gives 325→425 between 18:00 and 30:00.

**Gold and XP radius:** XP 1,400 (barracks) / 1,600 (champion constant). Gold radius ~1,000–1,250.

**Minion stats (ARAM values)** ([wiki ARAM][W-ARAM], [melee][W-Melee], [caster][W-Caster], [siege][W-Siege], [super][W-Super], upgrade sizes from [client barracks][CD-Map12]):

| Minion | HP | AD | AS | Range | Armor/MR | XP | Gold | Per-upgrade growth (client, every ~40–50 s) |
|---|---|---|---|---|---|---|---|---|
| Melee | 455 | 12 | 1.25 | 110 | 0 / 0 | 64 | ~20 | +27.25 HP (+30% growth), +1 AD |
| Caster | 290 | 23 | 0.667 | 550 | 0 / 0 | 32 | 17 | +9 HP, +2 AD, +0.625 armor |
| Siege | 805 | 40 | 1.0 | 300 | 0 / 0 (+3 per upgrade) | 94 | 52 | +34 HP, +1.5 AD |
| Super | ~1,600 base | 306 | 0.694 | 170 | 60 / 10 | 100 | 45 | +150 HP, +5 AD |

- On Summoner's Rift, minions deal 60% damage to champions and structures. Mayhem's client sets the unit→champion ratio to 1.0 (vs 0.5 in ARAM), so treat minion pressure on champions as meaningful.
- Area-of-effect damage deals **75%** to minions in ARAM.
- In ARAM you also get **some gold from nearby minion deaths** even without the last hit ([wiki Kill][W-Kill]).

### 4.7 Respawn, XP and gold quick reference

- **Respawn (seconds, by level 3→18):** 11, 13, 15, 17, 19, 21, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40. From 24:00, +2.5% per minute up to +25% ([client][CD-Map12]).
- **XP to level** (Howling Abyss, starting at level 3 with 0 XP) ([wiki XP][W-XP], matches client curve):

| Level | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| XP for this level | 478 | 510 | 750 | 780 | 880 | 980 | 1,080 | 1,180 | 1,280 | 1,380 | 1,480 | 1,580 | 1,680 | 1,780 | 1,880 |
| Cumulative from level 3 | 478 | 988 | 1,738 | **2,518** | 3,398 | 4,378 | 5,458 | **6,638** | 7,918 | 9,298 | 10,778 | **12,358** | 14,038 | 15,818 | 17,698 |

- **Kill XP by victim level** (client ARAM/Kiwi curve): 35, 95, 155, 215, 275, 335, 395, 455, 515 (levels 1–9), then 590, 640, 690 … +50 per level up to 990 at level 18. Level-difference multiplier 0.16 per level ([client][CD-Map12]).
- **Income:**
  - Mayhem passive gold is **510 g/min** (ARAM 360), so passive gold alone gives about 1,400 + 14 × 510 ≈ **8,500 g by 15:00**, before kills and minions.
  - Passive XP is 300/min.
  - In practice augment levels 7 / 11 / 15 land around 4–6 / 9–11 / 14–16 min **(estimate)**.

---

## 5. Core LoL combat math worth replicating

### 5.1 Damage and resistances

- **Post-mitigation damage:** `dmg × 100 / (100 + R)` for R ≥ 0, and `dmg × (2 − 100 / (100 − R))` for R < 0. The same formula applies to armor (physical) and MR (magic). True damage ignores it ([wiki Armor][W-Armor]).
- **Penetration order:** (1) flat armor reduction → (2) % armor reduction → (3) % armor penetration → (4) flat penetration (lethality). Lethality has been 1:1 flat pen at all levels since V14.1, and pen can't take armor below 0 ([wiki Armor pen][W-ArPen]).
- **Effective HP:** EHP = HP × (1 + R/100).

### 5.2 Attacks

- **Attack speed:** `AS = baseAS + ratio × bonusAS%`. For most champions ratio = base, so `AS = base × (1 + bonus)`. **Cap 3.003** normally; **5.0 in Mayhem**; floor 0.2 ([wiki AS][W-AS], [client][CD-Map12]).
- **Attack timer:** `1/AS`, split into windup then cooldown. Windup fraction = 0.3 + attackOffset (per champion). Windup time ≈ `(1/AS) × windup%` (when no windup modifier applies).
- Champion windup % (client `attackDelayCastOffsetPercent`; 0.30 + offset):

| Champion | Ahri | Annie | Darius | Ezreal | Garen | Jinx | Leona | Lux | Malphite | Miss Fortune | Sona | Yasuo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Windup % | 20.0 | 19.6 | 20.0 | 18.8 | 18.0 | 17.7 | 22.9 | 15.6 | 25.0 | 14.8 | 17.2 | 22.0 |

- **Critical strikes:** base crit damage is **200%** again since V26.01 (it was 175% for several years). Infinity Edge now gives +30% crit damage. Crit chance caps at 100% (Mayhem converts the excess, see §1.3). LoL uses pseudo-random crits; expected multiplier = `1 + critChance × (critDmg − 1)` ([wiki Crit][W-Crit], [Data Dragon][DDragon]). Jeweled Gauntlet / Vulnerability ability crits deal 145% + bonus crit damage.
- **Life steal:** heal = LS% × post-mitigation damage of basic attacks and on-hit. **Omnivamp:** heal = OV% × all post-mitigation damage. AoE, pets and DoTs heal at 33.3%, and vs minions/monsters at 33.3% (client constants).
- **Ability haste:** `CD = baseCD × 100 / (100 + AH)`. 100 AH = 50% CDR, 200 = 66.7%, cap 500 = 83.3% ([wiki AH][W-AH]).

### 5.3 Leveling

- **Stat growth:** `stat(n) = base + g × (n − 1) × (0.7025 + 0.0175 × (n − 1))`. At level 18 the multiplier is exactly 17.0. Bonus attack speed growth uses the same curve, multiplied by the AS ratio ([wiki stats][W-Stat]).
  - Example: Garen HP at level 18 = 690 + 98 × 17 = **2,356**. Mayhem adds +600 base HP for melee at level 18.

### 5.4 Champion base stats (patch 26.20)

Source: [Data Dragon 16.20][DDragon]. **AD growth comes from 16.1.1**, because Data Dragon reports 0 for AD growth from 16.10 onward (a data bug).

| Champion | HP (+/lvl) | HP5 (+) | Mana/res (+) | MP5 (+) | AD (+) | AS (+%) | Armor (+) | MR (+) | MS | Range |
|---|---|---|---|---|---|---|---|---|---|---|
| Ahri | 590 (104) | 2.5 (0.6) | 418 (25) | 8 (0.8) | 53 (3) | 0.668 (2.2) | 21 (4.2) | 30 (1.3) | 330 | 550 |
| Annie | 560 (96) | 5.5 (0.55) | 418 (25) | 8 (0.8) | 50 (2.65) | 0.61 (1.36) | 23 (4) | 30 (1.3) | 335 | 625 |
| Darius | 652 (114) | 10 (0.95) | 263 (58) | 6.6 (0.35) | 64 (5) | 0.625 (1) | 37 (5.2) | 32 (2.05) | 340 | 175 |
| Ezreal | 600 (102) | 4 (0.65) | 375 (70) | 8.5 (1) | 60 (3.25) | 0.625 (2.5) | 24 (4.2) | 33 (1.1) | 325 | 550 |
| Garen | 690 (98) | 8 (0.5) | none | – | 69 (4.5) | 0.625 (3.65) | 38 (4.2) | 32 (1.55) | 340 | 175 |
| Jinx | 630 (105) | 3.75 (0.5) | 260 (50) | 6.7 (1) | 59 (3.25) | 0.625 (1) | 26 (4.2) | 33 (1.1) | 325 | 525 |
| Leona | 646 (101) | 8.5 (0.85) | 302 (40) | 6 (0.8) | 60 (3) | 0.625 (2.9) | 43 (4.8) | 32 (2.05) | 335 | 125 |
| Lux | 580 (99) | 5.5 (0.55) | 440 (23.5) | 9 (0.8) | 54 (3.3) | 0.669 (3) | 21 (5.2) | 30 (1.3) | 330 | 550 |
| Malphite | 665 (104) | 7 (0.55) | 280 (60) | 7.3 (0.55) | 62 (4) | 0.736 (3.4) | 40 (4.95) | 28 (2.05) | 335 | 125 |
| Miss Fortune | 625 (100) | 3.75 (0.65) | 300 (40) | 8 (0.8) | 55 (2.4) | 0.656 (3) | 25 (4) | 33 (1.1) | 325 | 550 |
| Sona | 550 (91) | 5.5 (0.55) | 340 (45) | 11.5 (0.4) | 49 (3) | 0.644 (2.3) | 26 (4.2) | 30 (1.3) | 325 | 550 |
| Yasuo | 590 (110) | 6.5 (0.9) | Flow 100 | – | 60 (2.5) | 0.697 (3.5) | 32 (4.6) | 32 (2.05) | 345 | 175 |
| Ashe | 610 (101) | 3.5 (0.55) | 280 (35) | 7 (0.65) | 59 (3) | 0.658 (3) | 26 (4.6) | 33 (1.1) | 325 | 600 |
| Master Yi | 640 (105) | 7.5 (0.65) | 251 (42) | 7.25 (0.45) | 65 (2.5) | 0.679 (2.5) | 33 (5) | 32 (2.05) | 355 | 175 |
| Zed | 654 (99) | 7 (0.65) | Energy 200 | 50 | 63 (3.4) | 0.651 (3.3) | 32 (4.7) | 29 (2.05) | 345 | 125 |
| Veigar | 580 (108) | 6.5 (0.6) | 490 (26) | 8 (0.8) | 52 (2.7) | 0.625 (2.24) | 18 (5.2) | 32 (1.3) | 340 | 550 |
| Teemo | 615 (104) | 5.5 (0.65) | 334 (25) | 9.6 (0.45) | 54 (3) | 0.69 (3.38) | 24 (4.5) | 30 (1.3) | 330 | 500 |

- **Movement speed** across all 173 champions: **315–355**. Most are 325–345 (325: 19, 330: 37, 335: 43, 340: 37, 345: 28).
- **Attack range** buckets: 125 (45 champions), 150, 175 (28), then ranged 425–650, mostly 500/525/550 (37 at 550). Max 650 ([Data Dragon][DDragon]).
- **Collision radii:** default gameplay radius 65 (Malphite 80, Annie 55). Pathing radius ~35.
- **Kill gold:** see §1.2 (Mayhem client: base 200; first blood +90; assist pool 90; bounty +1 per 2 gold earned up to +600; −1 per 4 gold distributed; early-game 50%→100% by 3:30).
  - **Summoner's Rift reference:** 300 base kill gold (levels 1–6), +10 per level to 420 at level 18; assists share 50%; minimum bounty 50 ([wiki bounties][W-Bounty]).

---

## 6. Items: essentials for a Mayhem shop

### 6.1 Economy basics

- **Starting gold 1,400**, with shopping only on death or at spawn (see §1.2).
- A typical first back after the first death buys a full Legendary (about 2,500–3,300 g). Mayhem passive income is **510 g/min**, so 5–6 items by 18–20 min is normal.
- **Stat Bonus anvils** (750 g, level 16+) are the late-game gold sink.

### 6.2 Prices

Prices below are 26.20 Howling Abyss values from [Data Dragon][DDragon]. Passive numbers marked "~" are simplified or approximate; Data Dragon hides many template values.

**Components:**

| Component | Cost | Stats |
|---|---|---|
| Long Sword | 350 | 10 AD |
| Pickaxe | 875 | 25 AD |
| B.F. Sword | 1,300 | 40 AD |
| Dagger | 250 | 10% AS |
| Cloak of Agility | 600 | 15% crit |
| Amplifying Tome | 400 | 20 AP |
| Blasting Wand | 850 | 45 AP |
| Needlessly Large Rod | 1,200 | 65 AP |
| Ruby Crystal | 400 | 150 HP |
| Sapphire Crystal | 300 | 300 mana |
| Cloth Armor | 300 | 15 armor |
| Null-Magic Mantle | 400 | 20 MR |

**ARAM starters:** Guardian's Blade / Hammer / Horn / Orb at 950 g each (e.g. Orb: 50 AP, 150 HP, mana restore).

**Boots:**

| Boots | Cost | Stats |
|---|---|---|
| Boots | 300 | +25 MS |
| Berserker's Greaves | 1,100 | 30% AS, 45 MS |
| Sorcerer's Shoes | 1,100 | 12 magic pen, 45 MS |
| Plated Steelcaps | 1,200 | 25 armor, −10% damage from attacks, 45 MS |
| Mercury's Treads | 1,250 | 20 MR, 30% tenacity, 45 MS |
| Ionian Boots of Lucidity | 900 | 10 AH, 10 summoner haste, 45 MS |
| Boots of Swiftness | 1,000 | 55 MS, −25% slow effectiveness |

### 6.3 Curated legendary shortlist (34 items, simplified for a fun shop)

| Item | Cost | Stats | Passive / active (simplified) |
|---|---|---|---|
| Infinity Edge | 3,500 | 75 AD, 25% crit | +30% crit damage |
| Kraken Slayer | 3,000 | 45 AD, 40% AS, 4% MS | Every 3rd attack deals bonus physical (~150–200), up to +75% vs low-HP targets |
| Blade of the Ruined King | 3,200 | 40 AD, 25% AS, 10% LS | On-hit **9% (melee) / 6% (ranged) of current HP** (Mayhem value); 3 hits slow 30% |
| Guinsoo's Rageblade | 3,000 | 30 AD, 30 AP, 25% AS | On-hit 30 magic; +8% AS per attack (4 stacks); at full stacks every 3rd attack applies on-hit twice |
| Trinity Force | 3,333 | 36 AD, 30% AS, 333 HP, 15 AH | Spellblade: after a cast, next attack +~200% base AD; +20 MS on attack |
| Black Cleaver | 3,000 | 45 AD, 400 HP, 20 AH | Physical hits shred 6% armor (×5 = 30%); MS on hit |
| Sterak's Gage | 3,200 | 400 HP, 20% tenacity | +~45% base AD; below 30% HP gain a big decaying shield (60 s CD in Mayhem) |
| Bloodthirster | 3,400 | 80 AD, 15% LS | Excess life steal becomes a shield |
| Ravenous Hydra | 3,300 | 65 AD, 15 AH, 12% LS | Cleave (AoE on attack) + active AoE; life steal applies |
| Titanic Hydra | 3,300 | 40 AD, 600 HP | Cleave scales with max HP; empowered next cleave |
| Death's Dance | 3,300 | 60 AD, 50 armor, 15 AH | Delays ~30% (melee) of damage taken over 3 s; a takedown cleanses it and heals |
| Statikk Shiv | 3,000 | 45 AD, 45 AP, 30% AS | Energized attacks chain lightning (bounces, applies on-hit) |
| Runaan's Hurricane | 2,650 | 40% AS, 25% crit | Attacks fire bolts at 2 extra targets (apply on-hit) |
| Phantom Dancer | 2,650 | 65% AS, 25% crit, 10% MS | Ghosted |
| The Collector | 3,000 | 50 AD, 10 lethality, 25% crit | Executes champions below 5% HP; +25 g per kill |
| Rabadon's Deathcap | 3,500 | 130 AP | +30% total AP |
| Luden's Echo | 2,750 | 100 AP, 600 mana, 10 AH | Damaging abilities fire 6 echoes of bonus magic damage |
| Zhonya's Hourglass | 3,250 | 105 AP, 50 armor | Active: 2.5 s stasis (invulnerable, can't act) |
| Liandry's Torment | 3,000 | 60 AP, 300 HP | Abilities burn 2% max HP/s for 3 s; +2% damage per second in combat (max 6%) |
| Lich Bane | 2,900 | 100 AP, 6% MS, 10 AH | Spellblade: next attack after a cast deals bonus magic |
| Nashor's Tooth | 2,900 | 80 AP, 50% AS, 15 AH | On-hit bonus magic (~15 + 15% AP) |
| Void Staff | 3,000 | 95 AP | 40% magic penetration |
| Rylai's Crystal Scepter | 2,600 | 65 AP, 400 HP | Damaging abilities slow 30% for 1 s |
| **Rite of Ruin** (Mayhem) | 3,000 | 55 AP, 10 AH, 25% crit, 4% MS | Casting gives +2.5% crit for 6 s (max +20%); spells may shield you or a targeted ally (chance = crit chance) |
| Heartsteel | 2,500 | 700 HP | Charge a big attack against nearby champions: bonus physical damage, **permanent max HP = 10% of the damage (Mayhem)**; size grows with HP |
| Sunfire Aegis | 2,800 | 350 HP, 50 armor, 10 AH | Immolate: AoE magic burn around you after dealing or taking damage |
| Thornmail | 2,450 | 150 HP, 75 armor | Reflect magic damage when hit by attacks; 40% Grievous Wounds |
| Warmog's Armor | 3,100 | 1,000 HP | +12% item HP; with 2,000+ bonus HP, regenerates quickly after 8 s without damage |
| Spirit Visage | 2,700 | 400 HP, 50 MR, 10 AH | +25% heals and shields received |
| Randuin's Omen | 2,700 | 350 HP, 75 armor | −30% damage from crits; active AoE 70% slow |
| **Atma's Reckoning** (Mayhem) | 2,900 | 700 HP, 20% crit, 10 AH | +0–30% crit scaling with bonus HP. Tank-crit hybrid, combos with crit augments |
| **Sword of Blossoming Dawn** (Mayhem) | 2,350 | 45 AP, 200 HP, 12% heal & shield power, 15 AH | +1.2% AS per 1% heal & shield power; on-hit heals the lowest-HP nearby ally |
| Moonstone Renewer | 2,200 | 25 AP, 200 HP, 20 AH | Heals/shields on allies chain to another ally (30% heal / 35% shield) |
| Hextech Rocketbelt | 2,650 | 60 AP, 350 HP, 10 AH | Active dash plus missile fan |

**Quest-reward "super items"** (not purchasable):

| Item | Stats |
|---|---|
| The Golden Spatula | 90 AD, 110 AP, 40% AS, 15% crit, 200 HP, 20 armor/MR, 200 mana, 20 AH, 10% MS, 10% LS, burn aura |
| Ultra Hydra (6,000 g value) | 200 AD, 25 AH, 25 lethality, 1,000 HP, 15% omnivamp |
| Wooglet's Witchcap | 300 AP, 50 armor, 20 AH, +50% AP, stasis |
| Void Immolation | 1,000 HP, 100 armor, 80 MR, 25 AH, Immolate |

Sources: [Data Dragon][DDragon], [wiki][W-Mayhem].

---

## 7. Design takeaways: the 10 things to get right

1. **The death-gated augment loop.**
   - First pick on spawn, then picks at 7 / 11 / 15, claimable only while dead or on the platform (never in combat).
   - Dying should feel like a shopping-and-power-up moment. This loop is the mode's heartbeat.
2. **Shared-tier, three-card choice with one reroll per card.**
   - Roll Silver/Gold/Prismatic once per round for all 10 champions, show 3, allow 1 reroll per card, and add an occasional Golden Reroll.
   - Never repeat an augment within a game. Never make rounds 1 and 2 both Silver.
3. **Augments must change verbs, not just numbers.**
   - Prioritize the "transform" set: Draw Your Sword, Back To Basics, Ethereal Weapon, Echo Cast / Multishot / Spell Split, Ultimate Revolution, Can't Touch This, Biggest Snowball Ever, DropBear, Shark Bait, Clown College, Dimension Shift, Goliath / Giant Slayer, Tank / Shrink Engine.
   - Filter Ability Augments to spells that actually benefit, since Riot purged 450+ dead combinations.
4. **One straight lane, short games.**
   - Four turrets per side (outer, inhibitor turret, two nexus turrets), inhibitor and nexus, and **750** turret range with ramping champion damage.
   - Mayhem's **3,000-HP nexus and nexus turrets** keep games around **10–20 min**. No recall, no fountain regen, health relics only (22% area heal).
5. **Generous, fast economy.**
   - 1,400 start, **42.5 g per 5 s** passive from 1:00, 5 XP/s, start at level 3.
   - Kill bounties around 200 base, plus 750-g Stat Anvils at level 16+ as a late gold sink.
6. **Authentic combat math.**
   - Armor/MR `100/(100+R)` and the pen order; AS with windup (attack-move feel); crit 200%.
   - Haste `100/(100+AH)`; LoL stat growth curve; respawn table 11→40 s.
   - Mayhem specifics: **AS cap 5.0** and crit-overflow conversion, because augments push stats past normal LoL limits.
7. **Let snowball engines exist, but tax death.**
   - Unbounded stackers (Tank / Shrink Engine lose 65% on death, Slap Around 50%) and stat conversion are what create "my build came online" stories.
   - Counterweights: long late respawns, Combo Breaker (anti-chain-CC), and long-range damage reduction (85→70% beyond 1,000 units).
8. **Readable spectacle.**
   - Riot cut persistent always-on effects at launch and slowed auto-casters down while making each hit bigger. Every proc should be visible and punchy (sharks, Tibbers, trains, meteors) but not constant.
   - Show augment icons and tooltips clearly; players complained about unclear text.
9. **The Snowball (Mark/Dash) and ARAM flavour are core identity.**
   - 1,600-range true-damage skillshot (15–100) with dash recast, ~48 s CD.
   - Upgrades: Snowday, Snowblast, Pinball, Shark Tempest, Biggest Snowball Ever, Holy Snowball.
   - Also keep Poro-Snax, brushes and health relics as positional mini-objectives.
10. **Variance is the product, but protect the floor.**
    - Bots should pick augments sensibly (champion-tag matching), and weak picks should still be playable.
    - Optional layers in the spirit of Riot's later updates add replayability without new champions: quest augments (Urf's Champion → Golden Spatula), progression unlocks, and per-match "Headliner" rules (26.21).

---

## Sources

[W-Mayhem]: https://wiki.leagueoflegends.com/en-us/ARAM:_Mayhem
[W-Aug]: https://wiki.leagueoflegends.com/en-us/ARAM:_Mayhem/Augments
[W-AugData]: https://wiki.leagueoflegends.com/en-us/Module:MayhemAugmentData/data
[W-Patch]: https://wiki.leagueoflegends.com/en-us/ARAM:_Mayhem/Patch_history
[W-Old]: https://wiki.leagueoflegends.com/en-us/ARAM:_Mayhem/Old_content
[W-Anvil]: https://wiki.leagueoflegends.com/en-us/Stat_Bonus_(ARAM:_Mayhem)
[W-ARAM]: https://wiki.leagueoflegends.com/en-us/ARAM
[W-HA]: https://wiki.leagueoflegends.com/en-us/Howling_Abyss
[W-Lane]: https://wiki.leagueoflegends.com/en-us/Lane
[W-Turret]: https://wiki.leagueoflegends.com/en-us/Turret
[W-Inhib]: https://wiki.leagueoflegends.com/en-us/Inhibitor
[W-Relic]: https://wiki.leagueoflegends.com/en-us/Health_relic
[W-Minion]: https://wiki.leagueoflegends.com/en-us/Minion_(League_of_Legends)
[W-Melee]: https://wiki.leagueoflegends.com/en-us/Melee_minion
[W-Caster]: https://wiki.leagueoflegends.com/en-us/Caster_minion
[W-Siege]: https://wiki.leagueoflegends.com/en-us/Siege_minion
[W-Super]: https://wiki.leagueoflegends.com/en-us/Super_minion
[W-Kill]: https://wiki.leagueoflegends.com/en-us/Kill
[W-Bounty]: https://wiki.leagueoflegends.com/en-us/Champion_gold_bounties
[W-XP]: https://wiki.leagueoflegends.com/en-us/Experience_(champion)
[W-Stat]: https://wiki.leagueoflegends.com/en-us/Champion_statistic
[W-AS]: https://wiki.leagueoflegends.com/en-us/Attack_speed
[W-Armor]: https://wiki.leagueoflegends.com/en-us/Armor
[W-ArPen]: https://wiki.leagueoflegends.com/en-us/Armor_penetration
[W-Crit]: https://wiki.leagueoflegends.com/en-us/Critical_strike
[W-AH]: https://wiki.leagueoflegends.com/en-us/Ability_haste
[W-Mark]: https://wiki.leagueoflegends.com/en-us/Mark
[Riot-Dev1]: https://www.leagueoflegends.com/en-gb/news/dev/dev-bringing-mayhem-to-aram/
[Riot-Dev2]: https://www.leagueoflegends.com/en-us/news/dev/dev-augmentmaxxing-aram-mayhem
[Riot-Support]: https://support.riotgames.com/en-us/league-of-legends/events/league-of-legends-aram-mayhem-game-mode
[DDragon]: https://ddragon.leagueoflegends.com/cdn/16.20.1/data/en_US/item.json
[CD-Map12]: https://raw.communitydragon.org/latest/game/data/maps/shipping/map12/map12.bin.json
[CD-Kiwi]: https://raw.communitydragon.org/latest/game/maps/modespecificdata/kiwi.bin.json
[CD-Strings]: https://raw.communitydragon.org/latest/game/en_us/data/menu/en_us/lol.stringtable.json
[CD-PBE]: https://raw.communitydragon.org/pbe/game/en_us/data/menu/en_us/lol.stringtable.json
[Client]: file:///D:/Games/ARAM_Mayhem/tools/extracted/client/kiwi_list.txt
[AM-Tier]: https://arammayhem.com/augments/
[AM-263]: https://arammayhem.com/patch/26-3/
[AM-2613]: https://arammayhem.com/patch/26-13/
[AM-2620]: https://arammayhem.com/patch/26-20/
[AM-40]: https://arammayhem.com/articles/aram-mayhem-4-0/
[AM-Pris]: https://arammayhem.com/articles/prismatic-augment-tier-list/
[AM-Ez]: https://arammayhem.com/build/ezreal/
[Moba-Builds]: https://mobalytics.gg/lol/champions/thresh/mayhem-builds
[Reddit-Cadmus]: https://reddit.sentinel-team.org/posts/1qx145b/snapshots/2026-02-06T04%3A31%3A18.39767Z
[IBT-Hotfix]: https://www.ibtimes.com/league-legends-aram-mayhem-cuts-over-450-ability-augments-live-hotfix-3804331
[Inven]: https://www.invenglobal.com/articles/20050/riots-aram-mayhem-mode-delivers-big-fun-but-players-are-asking-for-a-permanent-release
[Inven2]: https://www.invenglobal.com/articles/20062/riot-games-extends-lol-aram-mayhem-mode-teases-major-update-in-patch-2603
[GameRiv-2621]: https://gameriv.com/lol-patch-26-21-brings-new-aram-mayhem-augments-get-jinxed-totentanz-and-more/
[Elofactory]: https://elofactory.gg/en/blog/aram-mayhem-broken-champion-synergies
[Mobafire-Mark]: https://www.mobafire.com/league-of-legends/summoner-spell/mark-dash-18

| Tag | What it is |
|---|---|
| W-* | League of Legends Wiki (official community wiki). Mode rules, augment data module (current revision 14 Oct 2026, patch 26.20), patch history, map/structure/minion pages, combat formulas |
| Riot-* | Official Riot dev blogs ("Bringing Mayhem to ARAM", "Augmentmaxxing ARAM: Mayhem") and the Riot support FAQ |
| DDragon | Riot Data Dragon 16.20.1 (items, champions, summoner spells) |
| CD-* | CommunityDragon mirrors of live and PBE client files (game-mode constants, death timers, XP curve, barracks/minion configs, augment-selection config, quest milestones, spell data values, localized tooltips) |
| Client | The local client extraction (223 augments with rarities), used as the catalogue backbone |
| AM-* | arammayhem.com (tier list with 195 entries, patch digests 26.3 / 26.13 / 26.20, Mayhem 4.0 preview, combo pages) |
| Others | Reddit thread with Riot Cadmus's statement (via mirror), IBTimes (450-combination hotfix), Inven Global, GameRiv, Elofactory, Mobafire, Mobalytics |
