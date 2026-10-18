extends RefCounted
## Economy, RNG and meta-augments (anvils, transmutes, quests).



static func register(reg: Dictionary) -> void:
	reg["ARAM_Stats"] = func(): return StatAnvils.make(2, 0.0, "Gain 2 Stat Bonuses (random stat shards suited to your champion).")
	reg["ARAM_StatsOnStats"] = func(): return StatAnvils.make(3, 0.3, "Gain 3 Stat Bonuses, with a higher chance of Gold and Prismatic shards.")
	reg["ARAM_StatsOnStatsOnStats"] = func(): return StatAnvils.make(4, 0.6, "Gain 4 Stat Bonuses, with a much higher chance of Gold and Prismatic shards.")
	reg["ARAM_TransmuteGold"] = func(): return Transmute.make("Gold", 1, "Gain one random Gold augment.")
	reg["ARAM_TransmutePrismatic"] = func(): return Transmute.make("Prismatic", 1, "Gain one random Prismatic augment.")
	reg["ARAM_TransmuteChaos"] = func(): return Transmute.make("", 2, "Gain TWO completely random augments of any tier.")
	reg["Donation"] = func(): return Donation.new()
	reg["ARAM_PandorasBox"] = func(): return PandorasBox.new()
	reg["KingMe"] = func(): return KingMe.new()
	reg["ARAM_Quest_UrfsChampion"] = func(): return UrfsChampion.new()


class StatAnvils extends Augment:
	const SHARDS := {
		"Silver": [{"ah": 11.0}, {"ap": 15.0}, {"armor": 12.0}, {"ad": 11.0}, {"as": 0.11}, {"crit": 0.08}, {"hp": 110.0},
			{"lethality": 8.0}, {"magic_pen": 8.0}, {"mr": 14.0}, {"ad": 8.0, "ap": 12.0}, {"as": 0.1, "ah": 8.0}, {"armor": 10.0, "mr": 10.0}],
		"Gold": [{"ah": 35.0}, {"ap": 50.0}, {"armor": 45.0}, {"ad": 35.0}, {"as": 0.35}, {"crit": 0.25}, {"hp": 375.0},
			{"lethality": 20.0}, {"magic_pen": 18.0}, {"mr": 45.0}, {"ad": 25.0, "ap": 25.0}, {"as": 0.25, "ah": 20.0}, {"armor": 30.0, "mr": 30.0}],
		"Prismatic": [{"armor_pen%": 0.175}, {"crit_dmg": 0.25}, {"hp%": 0.15, "size": 0.1}, {"magic_pen%": 0.175},
			{"ms%": 0.18, "size": -0.1}, {"omnivamp": 0.15}, {"heal_power": 0.25}, {"tenacity": 0.3}],
	}

	## Pick a shard for a champion (prefers its damage type).
	static func pick_shard(c, tier: String) -> Dictionary:
		var pool: Array = SHARDS[tier]
		var tags := AugmentDB.champion_tags(c)
		var best: Dictionary = pool[0]
		var best_s := -INF
		for i in 3:
			var s: Dictionary = pool[G.rng.randi() % pool.size()]
			var score := G.rng.randf()
			if "ap" in tags and (s.has("ap") or s.has("magic_pen") or s.has("magic_pen%") or s.has("ah")):
				score += 1.0
			if "ad" in tags and (s.has("ad") or s.has("lethality") or s.has("armor_pen%") or s.has("as") or s.has("crit")):
				score += 1.0
			if "tank" in tags and (s.has("hp") or s.has("armor") or s.has("mr") or s.has("hp%") or s.has("tenacity")):
				score += 1.0
			if score > best_s:
				best_s = score
				best = s
		return best

	var count := 2
	var luck := 0.0

	static func make(n: int, l: float, desc: String) -> StatAnvils:
		var a := StatAnvils.new()
		a.count = n
		a.luck = l
		a.power = 1.5 + n * 0.3
		a.description = desc
		return a

	func on_acquire(c) -> void:
		var total := {}
		var names := []
		for i in count:
			var r := G.rng.randf()
			var tier := "Silver"
			if r < 0.12 + luck * 0.5:
				tier = "Prismatic"
			elif r < 0.55 + luck:
				tier = "Gold"
			var s: Dictionary = pick_shard(c, tier)
			for k in s:
				total[k] = total.get(k, 0.0) + s[k]
			names.append(tier)
		stats = total
		var parts := []
		for k in total:
			var v: float = total[k]
			parts.append(("+%d%% %s" % [int(v * 100.0), k.replace("%", "")]) if absf(v) < 1.0 else ("+%d %s" % [int(v), k]))
		description = description + "\nRolled: " + ", ".join(parts)
		refresh_stats()


class Transmute extends Augment:
	var tier := "Gold"
	var n := 1

	static func make(t: String, count: int, desc: String) -> Transmute:
		var a := Transmute.new()
		a.tier = t
		a.n = count
		a.power = 4.0 if t == "Prismatic" else (2.5 if t == "Gold" else 3.0)
		a.description = desc
		return a

	func on_acquire(c) -> void:
		var m = c.match_ref
		var excl := {}
		for a in c.augments:
			excl[a.id] = true
		for i in n:
			var t := tier
			if t == "":
				t = ["Silver", "Gold", "Prismatic"][G.rng.randi() % 3]
			var ids := AugmentDB.roll(c, t, 1, excl)
			if ids.is_empty():
				continue
			excl[ids[0]] = true
			m.grant_augment(c, ids[0])


class Donation extends Augment:
	func _init() -> void:
		power = 2.5
		description = "Gain 1750 gold."

	func on_acquire(c) -> void:
		c.add_gold(1750.0)


class PandorasBox extends Augment:
	func _init() -> void:
		power = 3.0
		description = "Gain a random Prismatic augment AND every augment you already own is re-rolled into a random Prismatic augment."

	func on_acquire(c) -> void:
		var m = c.match_ref
		var old: Array = c.augments.filter(func(a): return a != self)
		var excl := {}
		for a in c.augments:
			excl[a.id] = true
		for a in old:
			c.augments.erase(a)
			c.remove_effect(a)
		for i in old.size() + 1:
			var ids := AugmentDB.roll(c, "Prismatic", 1, excl)
			if ids.is_empty():
				continue
			excl[ids[0]] = true
			m.grant_augment(c, ids[0])
		c.augments_changed.emit()


class KingMe extends Augment:
	var done := false

	func _init() -> void:
		power = 0.5
		description = "The first time you reach the enemy base (near their spawn platform), you are crowned: gain one random Prismatic augment."

	func on_tick(u, _dt: float) -> void:
		if done or u.dead:
			return
		var enemy_spawn: Vector3 = u.match_ref.spawn_points[1 - u.team]
		if G.flat_dist(u.global_position, enemy_spawn) < 30.0:
			done = true
			display_name = "King Me (Crowned!)"
			var ids := AugmentDB.roll(u, "Prismatic", 1, {})
			if not ids.is_empty():
				u.match_ref.grant_augment(u, ids[0])
			Vfx.burst(u.match_ref, u.global_position + Vector3(0, 2, 0), Color(1.0, 0.85, 0.3), 2.5, {"sparks": 60})
			G.announce("%s has been crowned!" % u.display_name, "King Me", G.COLOR_GOLD)


class UrfsChampion extends Augment:
	var takedowns := 0

	func _init() -> void:
		power = 2.0
		description = "QUEST: score 18 champion takedowns. REWARD: The Golden Spatula (90 AD, 110 AP, 40% AS, 15% crit, 200 HP, 20 armor/MR, 20 AH, 10% MS, 10% life steal)."
		counter_text = "0/18"

	func on_takedown(_v) -> void:
		if takedowns >= 18:
			return
		takedowns += 1
		counter_text = "%d/18" % takedowns
		if takedowns >= 18:
			counter_text = "✔"
			display_name = "Urf's Champion (Golden Spatula)"
			stats = {"ad": 90.0, "ap": 110.0, "as": 0.4, "crit": 0.15, "hp": 200.0, "armor": 20.0, "mr": 20.0, "ah": 20.0,
				"ms%": 0.1, "lifesteal": 0.1, "mana": 200.0}
			refresh_stats()
			G.announce("%s earned the Golden Spatula!" % owner.display_name, "Urf's Champion", G.COLOR_GOLD)
