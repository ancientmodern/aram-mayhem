class_name ItemDB
extends RefCounted
## Howling Abyss item shop catalogue (ids match League's, used for icons).
## Entry: [name, cost, stats, components, unique_group, effect_class_name, tags, description]

const STARTERS := [3112, 2051, 3177, 3184]
const BOOTS := [1001, 3006, 3020, 3047, 3111, 3158, 3009]

const CAT := {
	# ---- starters (ARAM Guardian items)
	3112: ["Guardian's Orb", 950, {"ap": 50.0, "hp": 150.0, "mana_regen": 2.0}, [], "guardian", "", ["mage", "starter"], "Restores mana over time."],
	2051: ["Guardian's Horn", 950, {"hp": 150.0, "hp_regen": 4.0}, [], "guardian", "GuardianHorn", ["tank", "starter"], "Reduces damage from champion attacks by 12."],
	3177: ["Guardian's Blade", 950, {"ad": 30.0, "hp": 150.0, "ah": 15.0}, [], "guardian", "", ["fighter", "starter"], ""],
	3184: ["Guardian's Hammer", 950, {"ad": 25.0, "hp": 150.0, "lifesteal": 0.1}, [], "guardian", "", ["marksman", "fighter", "starter"], ""],
	# ---- components
	1036: ["Long Sword", 350, {"ad": 10.0}, [], "", "", ["basic"], ""],
	1037: ["Pickaxe", 875, {"ad": 25.0}, [], "", "", ["basic"], ""],
	1038: ["B. F. Sword", 1300, {"ad": 40.0}, [], "", "", ["basic"], ""],
	1042: ["Dagger", 250, {"as": 0.1}, [], "", "", ["basic"], ""],
	1043: ["Recurve Bow", 700, {"as": 0.15}, [], "", "", ["basic"], ""],
	1018: ["Cloak of Agility", 600, {"crit": 0.15}, [], "", "", ["basic"], ""],
	1052: ["Amplifying Tome", 400, {"ap": 20.0}, [], "", "", ["basic"], ""],
	1026: ["Blasting Wand", 850, {"ap": 45.0}, [], "", "", ["basic"], ""],
	1058: ["Needlessly Large Rod", 1200, {"ap": 65.0}, [], "", "", ["basic"], ""],
	1028: ["Ruby Crystal", 400, {"hp": 150.0}, [], "", "", ["basic"], ""],
	1011: ["Giant's Belt", 900, {"hp": 350.0}, [1028], "", "", ["basic"], ""],
	1027: ["Sapphire Crystal", 300, {"mana": 300.0}, [], "", "", ["basic"], ""],
	1029: ["Cloth Armor", 300, {"armor": 15.0}, [], "", "", ["basic"], ""],
	1031: ["Chain Vest", 800, {"armor": 40.0}, [1029], "", "", ["basic"], ""],
	1033: ["Null-Magic Mantle", 400, {"mr": 20.0}, [], "", "", ["basic"], ""],
	1057: ["Negatron Cloak", 850, {"mr": 45.0}, [1033], "", "", ["basic"], ""],
	1053: ["Vampiric Scepter", 900, {"ad": 15.0, "lifesteal": 0.07}, [1036], "", "", ["basic"], ""],
	3133: ["Caulfield's Warhammer", 1050, {"ad": 20.0, "ah": 10.0}, [1036, 1036], "", "", ["basic"], ""],
	3067: ["Kindlegem", 800, {"hp": 200.0, "ah": 10.0}, [1028], "", "", ["basic"], ""],
	3044: ["Phage", 1100, {"hp": 200.0, "ad": 15.0}, [1028, 1036], "", "", ["basic"], ""],
	3057: ["Sheen", 700, {}, [], "", "Spellblade", ["basic"], "Spellblade: after using an ability, your next attack deals 100% base AD bonus physical damage (1.5s cooldown)."],
	3086: ["Zeal", 1050, {"as": 0.15, "crit": 0.15, "ms%": 0.07}, [1042, 1018], "", "", ["basic"], ""],
	3108: ["Fiendish Codex", 900, {"ap": 35.0, "ah": 10.0}, [1052], "", "", ["basic"], ""],
	3113: ["Aether Wisp", 900, {"ap": 30.0, "ms%": 0.04}, [1052], "", "", ["basic"], ""],
	3802: ["Lost Chapter", 1200, {"ap": 40.0, "mana": 300.0, "ah": 10.0}, [1052, 1027], "", "", ["basic"], ""],
	3035: ["Last Whisper", 1450, {"ad": 20.0, "armor_pen%": 0.18}, [1036, 1036], "", "", ["basic"], ""],
	3134: ["Serrated Dirk", 1000, {"ad": 20.0, "lethality": 10.0}, [1036, 1036], "", "", ["basic"], ""],
	3077: ["Tiamat", 1200, {"ad": 20.0}, [1036, 1036], "", "Cleave", ["basic"], "Cleave: attacks deal 40% AD physical damage to enemies around the target."],
	3801: ["Crystalline Bracer", 650, {"hp": 200.0, "hp_regen": 2.0}, [1028], "", "", ["basic"], ""],
	3145: ["Hextech Alternator", 1100, {"ap": 45.0}, [1052, 1052], "", "", ["basic"], ""],
	3211: ["Spectre's Cowl", 1250, {"hp": 250.0, "mr": 25.0}, [1028, 1033], "", "", ["basic"], ""],
	3082: ["Warden's Mail", 1000, {"armor": 40.0}, [1029, 1029], "", "", ["basic"], ""],
	6660: ["Bami's Cinder", 900, {"hp": 200.0, "ah": 5.0}, [1028], "immolate", "Immolate", ["basic"], "Immolate: in combat, deal 12 (+1% bonus health) magic damage per second to nearby enemies."],
	# ---- boots
	1001: ["Boots", 300, {"ms": 25.0}, [], "boots", "", ["boots"], ""],
	3006: ["Berserker's Greaves", 1100, {"as": 0.3, "ms": 45.0}, [1001, 1042, 1042], "boots", "", ["boots", "marksman"], ""],
	3020: ["Sorcerer's Shoes", 1100, {"magic_pen": 12.0, "ms": 45.0}, [1001], "boots", "", ["boots", "mage"], ""],
	3047: ["Plated Steelcaps", 1200, {"armor": 25.0, "ms": 45.0}, [1001, 1029], "boots", "Steelcaps", ["boots", "tank"], "Reduces damage taken from attacks by 10%."],
	3111: ["Mercury's Treads", 1250, {"mr": 20.0, "tenacity": 0.3, "ms": 45.0}, [1001, 1033], "boots", "", ["boots", "tank"], ""],
	3158: ["Ionian Boots of Lucidity", 900, {"ah": 10.0, "summoner_haste": 10.0, "ms": 45.0}, [1001], "boots", "", ["boots", "mage", "support"], ""],
	3009: ["Boots of Swiftness", 1000, {"ms": 55.0, "slow_resist": 0.25}, [1001], "boots", "", ["boots"], ""],
	# ---- marksman / fighter
	3031: ["Infinity Edge", 3500, {"ad": 75.0, "crit": 0.25, "crit_dmg": 0.3}, [1038, 1037, 1018], "", "", ["marksman", "crit"], "Critical strikes deal 30% more damage."],
	6672: ["Kraken Slayer", 3000, {"ad": 45.0, "as": 0.4, "ms%": 0.04}, [1037, 1043, 1042], "", "Kraken", ["marksman", "onhit"], "Bring It Down: every third attack deals 150-200 bonus physical damage, increased by up to 75% against low-health targets."],
	3153: ["Blade of the Ruined King", 3200, {"ad": 40.0, "as": 0.25, "lifesteal": 0.1}, [1053, 1043, 1037], "", "Botrk", ["marksman", "fighter", "onhit"], "Mist's Edge: attacks deal 9% (melee) / 6% (ranged) of the target's current health as bonus physical damage."],
	3124: ["Guinsoo's Rageblade", 3000, {"ad": 30.0, "ap": 30.0, "as": 0.25}, [1052, 1043, 1037], "", "Guinsoo", ["marksman", "onhit"], "Attacks deal 30 bonus magic damage on-hit and grant 8% attack speed (max 4 stacks). At max stacks every third attack applies on-hit effects twice."],
	3078: ["Trinity Force", 3333, {"ad": 36.0, "as": 0.3, "hp": 333.0, "ah": 15.0}, [3057, 3044, 1042], "spellblade", "Spellblade", ["fighter", "onhit"], "Spellblade: after using an ability, your next attack deals 200% base AD bonus physical damage (1.5s cooldown)."],
	3071: ["Black Cleaver", 3000, {"ad": 45.0, "hp": 400.0, "ah": 20.0}, [3044, 3067, 1037], "", "Cleaver", ["fighter"], "Carve: dealing physical damage to a champion shreds 6% armor for 6s (stacks 5 times)."],
	3053: ["Sterak's Gage", 3200, {"hp": 400.0, "tenacity": 0.2, "base_ad%": 0.45}, [1037, 1028, 1028], "", "Steraks", ["fighter", "tank"], "Lifeline: taking damage below 30% health grants a decaying shield for 60% of bonus health (60s cooldown)."],
	3072: ["Bloodthirster", 3400, {"ad": 80.0, "lifesteal": 0.15}, [1038, 1037, 1053], "", "Bloodthirster", ["marksman"], "Ichorshield: life steal beyond full health becomes a shield (up to 165-315)."],
	3074: ["Ravenous Hydra", 3300, {"ad": 65.0, "ah": 15.0, "lifesteal": 0.12}, [3077, 1053, 3133], "hydra", "Cleave", ["fighter"], "Cleave: attacks deal 40% AD physical damage to enemies around the target."],
	3748: ["Titanic Hydra", 3300, {"ad": 40.0, "hp": 600.0}, [3077, 1011, 1028], "hydra", "TitanicCleave", ["fighter", "tank"], "Colossus: attacks deal 1% (melee) / 0.75% (ranged) max health bonus physical damage to the target and enemies behind it."],
	6333: ["Death's Dance", 3300, {"ad": 60.0, "armor": 50.0, "ah": 15.0}, [1037, 1031, 3133], "", "DeathsDance", ["fighter"], "Ignore Pain: 30% (melee) / 15% (ranged) of damage taken is dealt over 3 seconds instead. Champion takedowns cleanse it and heal you."],
	3087: ["Statikk Shiv", 3000, {"ad": 45.0, "as": 0.3, "ms%": 0.04}, [3086, 1037], "", "Statikk", ["marksman", "onhit"], "Electroshock: every 100 energy (gained by moving and attacking), your next attack chains lightning to 6 enemies for 60-150 magic damage."],
	3085: ["Runaan's Hurricane", 2650, {"as": 0.4, "crit": 0.25, "ms%": 0.04}, [3086, 1043], "", "Runaans", ["marksman", "onhit"], "Wind's Fury: attacks fire bolts at up to 2 nearby enemies for 55% AD, applying on-hit effects."],
	3046: ["Phantom Dancer", 2650, {"as": 0.65, "crit": 0.25, "ms%": 0.1}, [3086, 1042, 1042], "", "", ["marksman", "crit"], "You are Ghosted."],
	6676: ["The Collector", 3000, {"ad": 50.0, "lethality": 10.0, "crit": 0.25}, [3134, 1037, 1018], "", "Collector", ["marksman"], "Death: damaging champions below 5% health executes them. Taxes: kills grant 25 extra gold."],
	3036: ["Lord Dominik's Regards", 3300, {"ad": 35.0, "crit": 0.25, "armor_pen%": 0.35}, [3035, 1018, 1036], "lastwhisper", "", ["marksman"], ""],
	3033: ["Mortal Reminder", 3000, {"ad": 35.0, "crit": 0.25, "armor_pen%": 0.3}, [3035, 1018], "lastwhisper", "Reminder", ["marksman"], "Physical damage applies 40% Grievous Wounds for 3 seconds."],
	6675: ["Navori Flickerblade", 2650, {"as": 0.4, "crit": 0.25, "ms%": 0.07}, [3086, 1042], "", "Navori", ["marksman"], "Transcendence: attacks reduce your basic abilities' remaining cooldowns by 15%."],
	3508: ["Essence Reaver", 3050, {"ad": 60.0, "crit": 0.25, "ah": 15.0}, [3057, 3133, 1018], "spellblade", "Spellblade", ["marksman"], "Spellblade: after using an ability, your next attack deals 100% base AD + 40% bonus AD bonus physical damage and restores mana."],
	3004: ["Manamune", 2900, {"ad": 35.0, "mana": 500.0, "ah": 15.0}, [1036, 1027, 3133], "", "", ["marksman"], "Awe: gain bonus AD equal to 2% maximum mana."],
	3142: ["Youmuu's Ghostblade", 2800, {"ad": 60.0, "lethality": 18.0, "ms%": 0.04}, [3134, 1036], "", "Youmuu", ["assassin"], "Active - Wraith Step: gain 20% movement speed and Ghosting for 6 seconds (45s cooldown)."],
	6692: ["Eclipse", 2900, {"ad": 60.0, "ah": 15.0}, [3133, 1037], "", "Eclipse", ["fighter"], "Ever Rising Moon: hitting a champion with 2 separate attacks or abilities deals 6% max health physical damage and grants a shield (6s cooldown)."],
	3161: ["Spear of Shojin", 3100, {"ad": 45.0, "hp": 450.0, "ah": 20.0}, [1037, 1028, 3067], "", "Shojin", ["fighter"], "Focused Will: ability hits grant a stack (6s, max 4) increasing ability damage by 3% each."],
	6631: ["Stridebreaker", 3300, {"ad": 50.0, "as": 0.2, "hp": 400.0}, [3077, 3044, 1042], "hydra", "Stridebreaker", ["fighter"], "Active - Halting Slash: deal 80% AD physical damage around you and slow enemies by 35% (15s cooldown)."],
	3156: ["Maw of Malmortius", 3200, {"ad": 60.0, "mr": 40.0, "ah": 15.0}, [1037, 1057, 1036], "lifeline", "Maw", ["fighter"], "Lifeline: taking magic damage below 30% health grants a 200 (+225% bonus AD) magic shield (90s cooldown)."],
	6673: ["Immortal Shieldbow", 3000, {"ad": 55.0, "crit": 0.25}, [1037, 1018, 1053], "lifeline", "Shieldbow", ["marksman"], "Lifeline: taking damage below 30% health grants a 320-720 shield for 3 seconds (90s cooldown)."],
	3091: ["Wit's End", 2800, {"as": 0.5, "mr": 45.0, "tenacity": 0.2}, [1043, 1057, 1042], "", "WitsEnd", ["fighter", "onhit"], "Fray: attacks deal 15-80 bonus magic damage on-hit."],
	# ---- mage
	3089: ["Rabadon's Deathcap", 3500, {"ap": 130.0, "ap%": 0.3}, [1058, 1058], "", "", ["mage"], "Increases your total ability power by 30%."],
	6655: ["Luden's Companion", 2750, {"ap": 100.0, "mana": 600.0, "ah": 10.0}, [3802, 1052, 1052], "", "Luden", ["mage"], "Fire: damaging an enemy with an ability fires 6 shots at nearby enemies for 50 (+10% AP) magic damage each, split between targets (12s cooldown)."],
	3157: ["Zhonya's Hourglass", 3250, {"ap": 105.0, "armor": 50.0}, [1058, 3082], "stasis", "Zhonya", ["mage"], "Active - Time Stop: become invulnerable and untargetable but unable to act for 2.5 seconds (120s cooldown)."],
	6653: ["Liandry's Torment", 3000, {"ap": 60.0, "hp": 300.0}, [1026, 1028, 1028], "", "Liandry", ["mage"], "Torment: abilities burn enemies for 2% max health magic damage per second for 3 seconds. Suffering: in combat with champions, deal up to 6% increased damage."],
	3100: ["Lich Bane", 2900, {"ap": 100.0, "ms%": 0.06, "ah": 10.0}, [3057, 1026], "spellblade", "LichBane", ["mage"], "Spellblade: after using an ability, your next attack deals 75% base AD + 45% AP bonus magic damage (1.5s cooldown)."],
	3115: ["Nashor's Tooth", 2900, {"ap": 80.0, "as": 0.5, "ah": 15.0}, [1043, 1026, 3108], "", "Nashor", ["mage", "onhit"], "Icathian Bite: attacks deal 15 (+15% AP) bonus magic damage on-hit."],
	3135: ["Void Staff", 3000, {"ap": 95.0, "magic_pen%": 0.4}, [1026, 1052], "", "", ["mage"], ""],
	3116: ["Rylai's Crystal Scepter", 2600, {"ap": 65.0, "hp": 400.0}, [1026, 1052, 1028], "", "Rylai", ["mage"], "Rimefrost: damaging abilities slow enemies by 30% for 1 second."],
	4645: ["Shadowflame", 3200, {"ap": 110.0, "magic_pen": 15.0}, [3145, 1058], "", "Shadowflame", ["mage"], "Cinderbloom: magic and true damage to champions below 40% health is increased by 20%."],
	3102: ["Banshee's Veil", 3000, {"ap": 105.0, "mr": 40.0}, [1058, 1033], "", "Banshee", ["mage"], "Annul: grants a spell shield that blocks the next enemy ability (40s cooldown)."],
	3118: ["Malignance", 2700, {"ap": 80.0, "mana": 600.0, "ult_ah": 20.0}, [3802, 1026], "", "", ["mage"], ""],
	4633: ["Riftmaker", 3100, {"ap": 70.0, "hp": 350.0, "ah": 15.0, "omnivamp": 0.08}, [1026, 3067], "", "Riftmaker", ["mage", "fighter"], "Void Corruption: in combat with champions, deal up to 8% increased damage."],
	4629: ["Cosmic Drive", 3000, {"ap": 70.0, "hp": 350.0, "ah": 25.0, "ms%": 0.04}, [3067, 3113, 3108], "", "", ["mage"], ""],
	3003: ["Archangel's Staff", 2900, {"ap": 70.0, "mana": 600.0, "ah": 25.0}, [3802, 3108], "", "Archangel", ["mage"], "Awe: gain ability power equal to 1% maximum mana."],
	3152: ["Hextech Rocketbelt", 2650, {"ap": 60.0, "hp": 350.0, "ah": 10.0}, [3145, 3067], "", "Rocketbelt", ["mage"], "Active - Supersonic: dash toward the cursor and fire a cone of missiles for 100 (+10% AP) magic damage (40s cooldown)."],
	# ---- tank / support
	3084: ["Heartsteel", 2500, {"hp": 700.0}, [1011, 3801], "", "Heartsteel", ["tank"], "Colossal Consumption: every 30s per champion, your next attack against them deals 70 (+6% bonus health) bonus physical damage and permanently grants 10% of that as maximum health."],
	3068: ["Sunfire Aegis", 2800, {"hp": 350.0, "armor": 50.0, "ah": 10.0}, [6660, 1031], "immolate", "Immolate", ["tank"], "Immolate: in combat, deal 20 (+1% bonus health) magic damage per second to nearby enemies."],
	3075: ["Thornmail", 2450, {"hp": 150.0, "armor": 75.0}, [3082, 1028], "", "Thornmail", ["tank"], "Thorns: when hit by an attack, deal 10 (+10% bonus armor) magic damage to the attacker and apply 40% Grievous Wounds."],
	3083: ["Warmog's Armor", 3100, {"hp": 1000.0, "hp_regen": 5.0}, [1011, 1011, 3801], "", "Warmogs", ["tank"], "Warmog's Heart: with at least 1500 bonus health, regenerate 3% max health per second after not taking damage for 6 seconds."],
	3065: ["Spirit Visage", 2700, {"hp": 400.0, "mr": 50.0, "ah": 10.0}, [3211, 3067], "", "Visage", ["tank"], "Boundless Vitality: heals and shields you receive are 25% stronger."],
	3143: ["Randuin's Omen", 2700, {"hp": 350.0, "armor": 75.0}, [3082, 1011], "", "Randuin", ["tank"], "Critical strikes deal 30% less damage to you. Active: slow nearby enemies by 70% for 2 seconds (60s cooldown)."],
	3110: ["Frozen Heart", 2900, {"armor": 65.0, "mana": 400.0, "ah": 20.0}, [3082, 1027], "", "", ["tank"], ""],
	4401: ["Force of Nature", 2800, {"hp": 350.0, "mr": 55.0, "ms%": 0.04}, [1057, 1028, 1028], "", "", ["tank"], ""],
	6665: ["Jak'Sho, The Protean", 3200, {"hp": 350.0, "armor": 50.0, "mr": 50.0}, [1011, 1029, 1033], "", "", ["tank"], ""],
	3742: ["Dead Man's Plate", 2900, {"hp": 350.0, "armor": 55.0, "ms%": 0.04}, [1031, 1028], "", "", ["tank"], ""],
	3039: ["Atma's Reckoning", 2900, {"hp": 700.0, "crit": 0.2, "ah": 10.0}, [1011, 1018], "", "Atma", ["tank", "fighter"], "Gain up to 30% critical strike chance based on bonus health."],
	4011: ["Sword of Blossoming Dawn", 2350, {"ap": 45.0, "hp": 200.0, "heal_power": 0.12, "ah": 15.0}, [1052, 1028], "", "Blossom", ["support"], "Attacks heal the lowest-health nearby ally for 15 (+15% AP)."],
	6617: ["Moonstone Renewer", 2200, {"ap": 25.0, "hp": 200.0, "ah": 20.0, "heal_power": 0.08}, [3067, 1052], "", "", ["support"], ""],
	3190: ["Locket of the Iron Solari", 2600, {"hp": 200.0, "armor": 30.0, "mr": 30.0, "ah": 10.0}, [3067, 1029, 1033], "", "Locket", ["support", "tank"], "Active - Devotion: shield nearby allies for 200 (+20 per level) for 2.5 seconds (90s cooldown)."],
	3107: ["Redemption", 2800, {"ap": 40.0, "hp": 200.0, "heal_power": 0.15, "ah": 15.0}, [3067, 1052], "", "Redemption", ["support"], "Active - Intervention: after 2 seconds, heal allies in a large area for 200 (+15 per level) and damage enemies (90s cooldown)."],
	# ---- Mayhem
	9999: ["Stat Bonus", 750, {}, [], "", "Anvil", ["consumable"], "Requires level 16. Grants a random stat shard suited to your champion (consumed instantly)."],
}

const BUILDS := {
	"Ahri": [3112, 6655, 3020, 4645, 3089, 3135, 3157],
	"Garen": [3177, 6631, 3047, 3071, 3053, 3742, 6333],
	"Darius": [3177, 6631, 3047, 3053, 3742, 6333, 4401],
	"Yasuo": [3184, 3006, 3031, 6672, 3072, 6333, 6673],
	"MasterYi": [3184, 3153, 3006, 3124, 3091, 6672, 6333],
	"Malphite": [2051, 3068, 3047, 3075, 3110, 3143, 6665],
	"Leona": [2051, 3190, 3111, 3068, 3075, 4401, 3065],
	"Lux": [3112, 6655, 3020, 4645, 3089, 3135, 3102],
	"Jinx": [3184, 6672, 3006, 3031, 3085, 3036, 3072],
	"Ezreal": [3177, 3078, 3158, 3004, 3071, 3036, 6333],
	"MissFortune": [3184, 6676, 3006, 3031, 3036, 3072, 6673],
	"Annie": [3112, 6655, 3020, 4645, 3089, 3157, 3135],
	"Sona": [3112, 6617, 3158, 3107, 4011, 3065, 3089],
	"Veigar": [3112, 6655, 3020, 3089, 4645, 3135, 3157],
}

const STAT_NAMES := {"ad": "Attack Damage", "ap": "Ability Power", "hp": "Health", "mana": "Mana", "armor": "Armor", "mr": "Magic Resist",
	"as": "Attack Speed", "crit": "Critical Strike Chance", "crit_dmg": "Critical Strike Damage", "ms": "Move Speed", "ms%": "Move Speed",
	"ah": "Ability Haste", "lifesteal": "Life Steal", "omnivamp": "Omnivamp", "lethality": "Lethality", "armor_pen%": "Armor Penetration",
	"magic_pen": "Magic Penetration", "magic_pen%": "Magic Penetration", "tenacity": "Tenacity", "heal_power": "Heal and Shield Power",
	"hp_regen": "Health Regen", "mana_regen": "Mana Regen", "ap%": "Ability Power", "base_ad%": "Base Attack Damage",
	"summoner_haste": "Summoner Spell Haste", "slow_resist": "Slow Resist", "ult_ah": "Ultimate Haste"}


# ------------------------------------------------------------------ UI-facing data (shop)
## League's shop stat filters (ItemShop statfilters, top to bottom) -> stat keys / tags that match.
const STAT_FILTERS := [
	["PhysicalDamage", "Attack Damage", ["ad", "base_ad%"]],
	["CriticalStrike", "Critical Strike", ["crit", "crit_dmg"]],
	["AttackSpeed", "Attack Speed", ["as"]],
	["OnHit", "On-Hit Effects", ["#onhit"]],
	["ArmorPen", "Armor Penetration", ["lethality", "armor_pen%"]],
	["AbilityPower", "Ability Power", ["ap", "ap%"]],
	["Mana", "Mana & Regeneration", ["mana", "mana_regen"]],
	["MagicPen", "Magic Penetration", ["magic_pen", "magic_pen%"]],
	["Health", "Health & Regeneration", ["hp", "hp_regen"]],
	["Armor", "Armor", ["armor"]],
	["MagicResist", "Magic Resist", ["mr"]],
	["AbilityHaste", "Ability Haste", ["ah", "ult_ah", "summoner_haste"]],
	["Movespeed", "Movement", ["ms", "ms%"]],
	["Vamp", "Life Steal & Vamp", ["lifesteal", "omnivamp"]],
]

## Short League-style blurbs for the recommended-item cards, by primary tag.
const ROLE_BLURB := {"mage": "Ability power and burst", "marksman": "Attack damage and crits", "fighter": "Damage and durability",
	"tank": "Durability and crowd control", "support": "Utility for allies", "assassin": "Lethality and burst",
	"onhit": "On-hit damage", "crit": "Critical strike damage", "boots": "Movement speed", "starter": "Starting item"}


static func has(item_id: int) -> bool:
	return CAT.has(item_id)


## League shop tier: "Starter", "Boots", "Basic", "Epic" or "Legendary".
static func tier_of(item_id: int) -> String:
	var tags := tags_of(item_id)
	if "starter" in tags:
		return "Starter"
	if "boots" in tags:
		return "Boots"
	if "consumable" in tags:
		return "Consumable"
	if "basic" in tags:
		return "Basic" if components_of(item_id).is_empty() else "Epic"
	return "Legendary"


## Items in the catalogue that use `item_id` as a direct component (League's "Builds Into").
static func builds_into(item_id: int) -> Array:
	var out := []
	for id in CAT:
		if item_id in components_of(id):
			out.append(id)
	out.sort_custom(func(a, b): return cost_of(a) < cost_of(b))
	return out


static func matches_stat_filter(item_id: int, filter_idx: int) -> bool:
	if filter_idx < 0 or filter_idx >= STAT_FILTERS.size():
		return true
	var st: Dictionary = CAT[item_id][2] if CAT.has(item_id) else {}
	for k in STAT_FILTERS[filter_idx][2]:
		if k.begins_with("#"):
			if k.substr(1) in tags_of(item_id):
				return true
		elif st.has(k):
			return true
	return false


## Case-insensitive name / stat search used by the shop search box.
static func matches_search(item_id: int, q: String) -> bool:
	if q == "":
		return true
	q = q.to_lower()
	if name_of(item_id).to_lower().contains(q):
		return true
	# initials ("ie" -> Infinity Edge) like League's search
	var initials := ""
	for w in name_of(item_id).split(" "):
		if w != "":
			initials += w[0].to_lower()
	if initials.begins_with(q):
		return true
	for k in (CAT[item_id][2] as Dictionary):
		if String(STAT_NAMES.get(k, k)).to_lower().contains(q):
			return true
	return false


## League's recommended page for a champion: {"starter": [...], "boots": [...], "core": [...]}.
static func recommended(alias: String) -> Dictionary:
	var build: Array = BUILDS.get(alias, [3177, 3047, 3071, 3053, 6333, 3742])
	var out := {"starter": [], "boots": [], "core": []}
	for id in build:
		var t := tier_of(id)
		if t == "Starter":
			out.starter.append(id)
		elif t == "Boots":
			out.boots.append(id)
		else:
			out.core.append(id)
	return out


static func blurb(item_id: int) -> String:
	for t in tags_of(item_id):
		if ROLE_BLURB.has(t) and t != "basic":
			return ROLE_BLURB[t]
	return ""


static func name_of(item_id: int) -> String:
	return CAT[item_id][0] if CAT.has(item_id) else str(item_id)


static func cost_of(item_id: int) -> int:
	return int(CAT[item_id][1]) if CAT.has(item_id) else 0


static func components_of(item_id: int) -> Array:
	return CAT[item_id][3] if CAT.has(item_id) else []


static func group_of(item_id: int) -> String:
	return CAT[item_id][4] if CAT.has(item_id) else ""


static func tags_of(item_id: int) -> Array:
	return CAT[item_id][6] if CAT.has(item_id) else []


static func stat_line(k: String, v: float) -> String:
	var nm: String = STAT_NAMES.get(k, k)
	var pct := k.ends_with("%") or k in ["as", "crit", "crit_dmg", "lifesteal", "omnivamp", "tenacity", "heal_power", "slow_resist"]
	if pct:
		return "+%d%% %s" % [int(round(v * 100.0)), nm]
	return "+%d %s" % [int(round(v)), nm]


static func create(item_id: int) -> Item:
	if not CAT.has(item_id):
		return null
	var e: Array = CAT[item_id]
	var it: Item
	var cls: String = e[5]
	if cls != "" and ItemFx.has_class(cls):
		it = ItemFx.make(cls)
	else:
		it = Item.new()
	it.item_id = item_id
	it.id = "item_%d" % item_id
	it.display_name = e[0]
	it.cost = int(e[1])
	it.stats = (e[2] as Dictionary).duplicate()
	it.components = e[3]
	it.unique_group = e[4]
	it.item_tags = e[6]
	it.description = e[7]
	it.icon = Assets.item_icon(item_id)
	return it


## Price to buy `item_id` for champion c after owned components are consumed. Returns [price, consumed_items].
static func price_for(c, item_id: int) -> Array:
	var owned: Array = c.items.duplicate()
	var consumed := []
	var price := cost_of(item_id)
	_discount(item_id, owned, consumed)
	for it in consumed:
		price -= it.cost
	return [price, consumed]


static func _discount(item_id: int, owned: Array, consumed: Array) -> void:
	for comp in components_of(item_id):
		var found = null
		for it in owned:
			if it.item_id == comp:
				found = it
				break
		if found != null:
			owned.erase(found)
			consumed.append(found)
		else:
			_discount(comp, owned, consumed)


## Can the champion buy this now? Returns "" or a reason.
static func buy_block_reason(c, item_id: int) -> String:
	if not CAT.has(item_id):
		return "unknown"
	if not c.can_shop():
		return "You can only shop while dead or in base"
	if item_id == 9999:
		if c.level < 16:
			return "Requires level 16"
		var p0 := price_for(c, item_id)
		return "" if c.gold >= p0[0] else "Not enough gold"
	var p := price_for(c, item_id)
	if c.gold < p[0]:
		return "Not enough gold"
	var slots_after: int = c.items.size() - p[1].size() + 1
	if slots_after > 6:
		return "Inventory full"
	var grp := group_of(item_id)
	if grp != "":
		for it in c.items:
			if it.unique_group == grp and not (it in p[1]):
				return "Only one %s item allowed" % grp
	return ""


static func buy(c, item_id: int) -> bool:
	if buy_block_reason(c, item_id) != "":
		return false
	var p := price_for(c, item_id)
	c.gold -= p[0]
	for it in p[1]:
		c.remove_item(it)
	if item_id == 9999:
		var anvil := create(9999)
		anvil.stats = AnvilShard.roll(c)
		anvil.hidden = true
		c.add_effect(anvil)
		c.anvils.append(anvil)
		c.items_changed.emit()
		return true
	c.add_item(create(item_id))
	return true


static func sell(c, it: Item) -> void:
	c.gold += int(it.cost * 0.7)
	c.remove_item(it)


## Next purchase for a bot following its build. Returns item id or -1.
static func bot_next_purchase(c) -> int:
	var build: Array = BUILDS.get(c.alias, [3177, 3047, 3071, 3053, 6333, 3742])
	for target in build:
		if _owns(c, target):
			continue
		if target in STARTERS and c.items.size() > 0:
			continue
		if buy_block_reason(c, target) == "":
			return target
		# buy the most expensive affordable component on the path
		var comp := _best_component(c, target)
		if comp > 0:
			return comp
		return -1
	if c.level >= 16 and c.gold >= 750 and c.items.size() >= 6:
		return 9999
	return -1


static func _owns(c, item_id: int) -> bool:
	for it in c.items:
		if it.item_id == item_id:
			return true
	return false


static func _best_component(c, target: int) -> int:
	var best := -1
	var best_cost := 0
	var stack: Array = components_of(target).duplicate()
	while not stack.is_empty():
		var comp: int = stack.pop_back()
		if _owns(c, comp):
			continue
		if buy_block_reason(c, comp) == "" and cost_of(comp) > best_cost:
			best = comp
			best_cost = cost_of(comp)
		stack += components_of(comp)
	return best


class AnvilShard extends RefCounted:
	static func roll(c) -> Dictionary:
		var r := G.rng.randf()
		var tier := "Silver" if r < 0.5 else ("Gold" if r < 0.88 else "Prismatic")
		var meta = load("res://src/augments/sets/aug_meta.gd")
		return meta.StatAnvils.pick_shard(c, tier)
