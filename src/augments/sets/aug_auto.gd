extends RefCounted
## Auto-cast augments: free extra abilities that fire on their own.


static func register(reg: Dictionary) -> void:
	reg["ARAM_Firefox"] = func(): return FireFox.new()
	reg["ARAM_DivineIntervention"] = func(): return DivineIntervention.new()
	reg["EndlessDecimation"] = func(): return EndlessDecimation.new()
	reg["ARAM_OkBoomerang"] = func(): return OkBoomerang.new()
	reg["Sonata"] = func(): return Sonata.new()
	reg["PromQueen"] = func(): return PromQueen.new()
	reg["ARAM_QuantumComputing"] = func(): return QuantumComputing.new()
	reg["ARAM_InfernoTriggered"] = func(): return TriggeredInferno.new()


## Base for auto-casters: cooldown that only ticks, and an "in combat" helper.
class AutoCast extends Augment:
	var cd := 0.0
	var base_cd := 10.0

	func on_tick(u, dt: float) -> void:
		if u.dead:
			return
		cd = maxf(0.0, cd - dt)
		if cd <= 0.0 and try_fire(u):
			cd = base_cd

	func try_fire(_u) -> bool:
		return false

	func hud_counter() -> String:
		return "" if cd <= 0.0 else str(int(ceil(cd)))

	func nearest_enemy_champ(u, r_m: float):
		var best = null
		var bd := INF
		for e in u.match_ref.enemies_in_radius(u.team, u.global_position, r_m, true):
			var d: float = G.flat_dist(e.global_position, u.global_position)
			if d < bd:
				bd = d
				best = e
		return best


class FireFox extends AutoCast:
	func _init() -> void:
		power = 2.0
		base_cd = 7.0
		description = "Every 7 seconds, automatically cast Fox-Fire: gain 25% decaying movement speed and release 3 flames that seek nearby enemies for 35-160 (+25% bonus AD) (+25% AP) adaptive damage."

	func try_fire(u) -> bool:
		var targets: Array = u.match_ref.enemies_in_radius(u.team, u.global_position, 5.5)
		if targets.is_empty():
			return false
		targets.sort_custom(func(a, b):
			var sa: float = G.flat_dist(a.global_position, u.global_position) - (3.0 if a.kind == G.Kind.CHAMPION else 0.0)
			var sb: float = G.flat_dist(b.global_position, u.global_position) - (3.0 if b.kind == G.Kind.CHAMPION else 0.0)
			return sa < sb)
		K.haste(u, 0.25, 2.0, u, true, "firefox_ms")
		var dmg: float = lvl_lerp(35.0, 160.0) + 0.25 * u.stats.bonus_ad + 0.25 * u.stats.ap
		var hits := {}
		var self_ref := self
		for i in 3:
			var tgt = targets[mini(i, targets.size() - 1)]
			var from: Vector3 = u.global_position + Vector3(cos(i * 2.1), 1.2, sin(i * 2.1)) * 1.2
			var mi := Missile.new()
			mi.setup_homing(u, from, tgt, 13.0)
			mi.visual = Vfx.orb(Color(1.0, 0.5, 0.2), 0.38, false)
			mi.on_hit = func(_m, t):
				var n: int = hits.get(t, 0)
				hits[t] = n + 1
				self_ref.proc(t, dmg * (1.0 if n == 0 else 0.3), self_ref.adaptive_type(), "firefox")
			u.match_ref.add_missile(mi, from)
		return true


class DivineIntervention extends AutoCast:
	func _init() -> void:
		power = 2.0
		base_cd = 35.0
		description = "Automatically call down a protective star when fighting. After 2.5 seconds, you and allied champions within 400 units become invulnerable for 2.5 seconds (35s cooldown)."

	func try_fire(u) -> bool:
		if u.match_ref.time - u.last_combat_time > 2.0 or u.hp_ratio() > 0.6:
			return false
		var m = u.match_ref
		var pos: Vector3 = u.global_position
		var star := Vfx.orb(Color(1.0, 0.9, 0.5), 1.0, true)
		m.add_fx(star, pos + Vector3(0, 9, 0))
		var tw := star.create_tween()
		tw.tween_property(star, "global_position", pos + Vector3(0, 1.0, 0), 2.5).set_ease(Tween.EASE_IN)
		Vfx.ground_circle(m, pos, 4.0, Color(1.0, 0.9, 0.4, 0.7), 2.6, 0.2)
		m.after(2.5, func():
			star.detach_and_fade()
			Vfx.burst(m, pos + Vector3(0, 1, 0), Color(1.0, 0.92, 0.5), 4.0)
			for a in m.allies_in_radius(u.team, pos, 4.0):
				K.buff(a, "divine_intervention", 2.5, {}, u, {"name": "Divine Intervention", "cc": Buff.CC.INVULNERABLE})
				Vfx.shield_bubble(a, Color(1.0, 0.9, 0.5), 2.5, 1.1))
		return true


class EndlessDecimation extends AutoCast:
	func _init() -> void:
		power = 2.5
		base_cd = 8.0
		description = "In combat, automatically cast Decimate: after 1.25s deal 100-400 (+60% AD) (+40% AP) physical damage around you (half in the inner circle). Each champion hit by the blade heals 18% missing health and lowers the cooldown."

	func try_fire(u) -> bool:
		if u.match_ref.enemies_in_radius(u.team, u.global_position, 4.6, true).is_empty():
			return false
		var m = u.match_ref
		var self_ref := self
		var ring := Vfx.aura(u, Color(0.9, 0.15, 0.1), 4.6, 1.25)
		m.after(1.25, func():
			if u.dead:
				return
			Vfx.ring(m, u.global_position, Color(0.85, 0.12, 0.1), 4.6, 0.35, 0.25, 0.0)
			var dmg: float = self_ref.lvl_lerp(100.0, 400.0) + 0.6 * u.stats.ad + 0.4 * u.stats.ap
			var champs := 0
			for e in m.enemies_in_radius(u.team, u.global_position, 4.6):
				var inner: bool = G.flat_dist(e.global_position, u.global_position) < 2.4
				self_ref.proc(e, dmg * (0.5 if inner else 1.0), G.DmgType.PHYSICAL, "decimate")
				if not inner and e.kind == G.Kind.CHAMPION:
					champs += 1
			if champs > 0:
				Combat.heal(u, u, (u.stats.max_hp - u.hp) * 0.18 * champs)
				self_ref.cd = maxf(3.0, self_ref.cd * pow(0.9, champs)))
		return true


class OkBoomerang extends AutoCast:
	func _init() -> void:
		power = 2.0
		base_cd = 10.0
		description = "Automatically throw a boomerang blade at the nearest enemy champion within 1250 units, dealing 40-200 (+30% bonus AD) (+20% AP) adaptive damage to enemies hit, out and back (10s cooldown)."

	func try_fire(u) -> bool:
		var t = nearest_enemy_champ(u, 12.5)
		if t == null:
			return false
		var m = u.match_ref
		var dmg: float = lvl_lerp(40.0, 200.0) + 0.3 * u.stats.bonus_ad + 0.2 * u.stats.ap
		var from: Vector3 = u.global_position + Vector3(0, 1.0, 0)
		var dir := G.flat_dir(u.global_position, t.global_position)
		var self_ref := self
		var mi := Missile.new()
		mi.setup_linear(u, from, dir, 16.0, 12.0, 0.7)
		mi.pierce = true
		mi.visual = Vfx.orb(Color(1.0, 0.8, 0.3), 0.55, false)
		mi.on_hit = func(_m, e): self_ref.proc(e, dmg, self_ref.adaptive_type(), "boomerang")
		mi.on_end = func(_m, pos):
			var back := Missile.new()
			back.setup_homing(u, pos, u, 18.0)
			back.mode = Missile.Mode.FOLLOW
			back.collides = true
			back.pierce = true
			back.width = 0.7
			back.visual = Vfx.orb(Color(1.0, 0.8, 0.3), 0.55, false)
			back.on_hit = func(m2, e):
				if e == u:
					m2.finish(u.global_position)
					return
				self_ref.proc(e, dmg, self_ref.adaptive_type(), "boomerang")
			back.on_move = func(m3, _dt):
				if G.flat_dist(m3.global_position, u.global_position) < 0.7:
					m3.finish(u.global_position)
			m.add_missile(back, pos)
		m.add_missile(mi, from)
		return true


class Sonata extends AutoCast:
	var aria := true

	func _init() -> void:
		power = 2.0
		base_cd = 10.0
		description = "Every 10 seconds, alternately auto-cast Aria (heal yourself and the most wounded nearby ally for 60 (+60% AP)) and Celerity (+30% movement speed for you, +20% for nearby allies)."

	func try_fire(u) -> bool:
		var m = u.match_ref
		if aria:
			var best = u
			for a in m.allies_in_radius(u.team, u.global_position, 10.0):
				if a.hp_ratio() < best.hp_ratio():
					best = a
			if best.hp_ratio() > 0.95 and u.hp_ratio() > 0.95:
				return false
			var amt: float = 60.0 + 0.6 * u.stats.ap
			Combat.heal(u, u, amt)
			if best != u:
				Combat.heal(u, best, amt)
			Vfx.ring(m, u.global_position, Color(0.4, 1.0, 0.6), 4.0, 0.5)
		else:
			K.haste(u, 0.3, 7.0, u, false, "sonata_ms")
			for a in m.allies_in_radius(u.team, u.global_position, 4.0):
				if a != u:
					K.haste(a, 0.2, 3.0, u, false, "sonata_ms")
			Vfx.ring(m, u.global_position, Color(0.8, 0.5, 1.0), 4.0, 0.5)
		aria = not aria
		return true


class PromQueen extends AutoCast:
	func _init() -> void:
		power = 2.5
		base_cd = 35.0
		description = "Auto-cast The Quickness when fighting: sprint for 6 seconds with 50% movement speed and ghosting. Enemies you touch are knocked down and charmed for 1.5 seconds (35s cooldown)."

	func try_fire(u) -> bool:
		if nearest_enemy_champ(u, 6.0) == null:
			return false
		var m = u.match_ref
		K.buff(u, "prom_queen", 6.0, {"ms%": 0.5}, u, {"name": "The Quickness", "cc": Buff.CC.GHOSTED})
		var trail := Vfx.rising(u, Color(1.0, 0.5, 0.85), 6.0, 40, 0.5)
		var charmed := {}
		m.add_ticker(6.0, func(_dt):
			if u.dead:
				return false
			for e in m.enemies_in_radius(u.team, u.global_position, 1.4, true):
				if not charmed.has(e):
					charmed[e] = true
					K.charm(e, 1.5, u, 0.6)
					Vfx.burst(m, e.global_position + Vector3(0, 1, 0), Color(1.0, 0.45, 0.8), 1.0, {"ring": false})
			return true)
		return true


class QuantumComputing extends AutoCast:
	func _init() -> void:
		power = 2.5
		base_cd = 30.0
		description = "When an enemy champion is within 650 units, auto-cast a sweeping strike after 0.75s: 200-350 (+75% bonus AD) (+45% AP) physical damage. Enemies on the outer edge take +10% max health, are slowed by 80% and heal you."

	func try_fire(u) -> bool:
		if nearest_enemy_champ(u, 6.5) == null:
			return false
		var m = u.match_ref
		var self_ref := self
		var a := Vfx.aura(u, Color(0.5, 0.95, 1.0), 6.5, 0.8)
		m.after(0.75, func():
			if u.dead:
				return
			Vfx.ring(m, u.global_position, Color(0.5, 0.95, 1.0), 6.5, 0.35, 0.2, 0.0)
			var dmg: float = self_ref.lvl_lerp(200.0, 350.0) + 0.75 * u.stats.bonus_ad + 0.45 * u.stats.ap
			for e in m.enemies_in_radius(u.team, u.global_position, 6.5):
				var outer: bool = G.flat_dist(e.global_position, u.global_position) > 4.8
				var d := dmg
				if outer:
					var bonus: float = 0.1 * e.stats.max_hp
					d += bonus
					K.slow(e, 0.8, 2.0, u, true)
					Combat.heal(u, u, bonus * 0.8)
				self_ref.proc(e, d, G.DmgType.PHYSICAL, "quantum"))
		return true


class TriggeredInferno extends Augment:
	var style := 0
	var last_target = null
	var timer := 0.0
	var cd := 0.0

	func _init() -> void:
		power = 2.5
		description = "Hitting a different champion than your last hit grants Style (max 7, +4% move speed each). At 7 Style, unleash a 2-second torrent: shoot enemies within 600 units every 0.2s for 20-40 (+40% AD) (+25% AP) physical damage, doubled below 30% health."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)
		if style > 0:
			timer -= dt
			if timer <= 0.0:
				style = 0
				counter_text = ""
				refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"ms%": 0.04 * style}

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION or info.tag == "inferno" or info.is_dot:
			return
		if t != last_target:
			last_target = t
			style = mini(7, style + 1)
			timer = 6.0
			counter_text = str(style)
			refresh_stats()
		if style >= 7 and cd <= 0.0:
			cd = 5.0
			style = 0
			counter_text = ""
			_torrent()

	func _torrent() -> void:
		var o = owner
		var m = o.match_ref
		var acc := {"t": 0.0}
		var self_ref := self
		m.add_ticker(2.0, func(dt):
			if o.dead:
				return false
			acc.t += dt
			if acc.t < 0.2:
				return true
			acc.t = 0.0
			for e in m.enemies_in_radius(o.team, o.global_position, 6.0):
				var d: float = self_ref.lvl_lerp(20.0, 40.0) + 0.4 * o.stats.ad + 0.25 * o.stats.ap
				if e.kind == G.Kind.MINION:
					d *= 0.25
				if e.hp_ratio() < 0.3:
					d *= 2.0
				Combat.deal(o, e, d, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "inferno"})
				Vfx.beam(m, o.global_position + Vector3(0, 1.2, 0), e.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.2), 0.08, 0.1)
			return true)
