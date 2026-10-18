extends RefCounted
## Snowball (Mark / Dash) upgrades. All of them grant Mark if you don't have it.


static func register(reg: Dictionary) -> void:
	reg["ARAM_Snowday"] = func(): return Snowday.new()
	reg["SharkTempest"] = func(): return SharkTempest.new()
	reg["Snowbomb"] = func(): return Snowblast.new()
	reg["BiggestSnowballEver"] = func(): return BiggestSnowball.new()
	reg["GoldenSnowball"] = func(): return HolySnowball.new()


class SnowAug extends Augment:
	var haste := 0.0

	func on_acquire(c) -> void:
		var has := false
		for s in c.summoners:
			if s != null and s.id == "Mark":
				has = true
		if not has:
			Summoners.set_spell(c, 1, "Mark")

	func modify_cooldown(ab, cd: float) -> float:
		if ab.is_summoner and ab.id == "Mark" and haste > 0.0:
			return cd * 100.0 / (100.0 + haste)
		return cd


class Snowday extends SnowAug:
	func _init() -> void:
		power = 1.5
		haste = 100.0
		description = "Your Mark deals 100% increased damage and its cooldown is reduced by the equivalent of 100 haste."

	func snowball_damage_mult() -> float:
		return 2.0


class SharkTempest extends SnowAug:
	func _init() -> void:
		power = 2.0
		haste = 0.0
		description = "Sharks circle your snowball, dealing 100-200 magic damage and slowing 40% along its path. When it hits a champion, the sharks circle the target for 3 seconds, dealing 30-90 (+25% bonus AD) (+15% AP) magic damage per second."

	func modify_snowball(mi) -> void:
		var o = owner
		var hit := {}
		var self_ref := self
		mi.visual.add_child(Vfx.sprite(Color(0.3, 0.55, 1.0), 2.4, 0.8))
		mi.on_move = func(m2, _dt):
			for e in o.match_ref.enemies_in_radius(o.team, m2.global_position, 3.0):
				if not hit.has(e):
					hit[e] = true
					self_ref.proc(e, self_ref.lvl_lerp(100.0, 200.0), G.DmgType.MAGIC, "shark")
					K.slow(e, 0.4, 1.0, o)

	func on_snowball_hit(u) -> void:
		var o = owner
		var m = o.match_ref
		var dps: float = lvl_lerp(30.0, 90.0) + 0.25 * o.stats.bonus_ad + 0.15 * o.stats.ap
		var fx := Vfx.aura(u, Color(0.3, 0.55, 1.0), 4.25, 3.0)
		var acc := {"t": 0.0}
		var self_ref := self
		m.add_ticker(3.0, func(dt):
			if u.dead:
				return false
			acc.t += dt
			if acc.t >= 0.5:
				acc.t = 0.0
				for e in m.enemies_in_radius(o.team, u.global_position, 4.25):
					self_ref.proc(e, dps * 0.5, G.DmgType.MAGIC, "shark")
					K.slow(e, 0.4, 0.6, o)
			return true)


class Snowblast extends SnowAug:
	func _init() -> void:
		power = 1.0
		haste = 100.0
		description = "Your Mark Dash deals 100% increased damage, knocks up the target for 0.5 seconds and knocks back nearby enemies. Mark's cooldown is reduced by the equivalent of 100 haste."

	func on_snowball_dash_arrive(t) -> void:
		if t == null or not is_instance_valid(t) or t.dead:
			return
		proc(t, 10.0 + 5.0 * owner.level, G.DmgType.TRUE, "snowblast")
		K.knockup(t, 0.5, owner)
		for e in owner.match_ref.enemies_in_radius(owner.team, t.global_position, 3.0):
			if e != t:
				e.knockback(t.global_position, 2.5, 0.4, owner)
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 0.6, 0), Color(0.85, 0.95, 1.0), 3.0)


class BiggestSnowball extends SnowAug:
	func _init() -> void:
		power = 2.5
		haste = 100.0
		description = "Your Mark becomes a giant snowball that passes through non-champions (stunning them). On champion hit it explodes for 200-350 (+100% bonus AD) (+60% AP) magic damage, knocking up for 0.75s and slowing by 20%."

	func modify_snowball(mi) -> void:
		var o = owner
		mi.width = 1.5
		mi.hits_minions = false
		mi.visual.scale = Vector3.ONE * 3.0
		var stunned := {}
		mi.on_move = func(m2, _dt):
			for e in o.match_ref.enemies_in_radius(o.team, m2.global_position, 1.5):
				if e.kind != G.Kind.CHAMPION and not stunned.has(e):
					stunned[e] = true
					K.stun(e, 1.25, o)

	func on_snowball_hit(u) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = u.global_position
		Vfx.burst(m, pos + Vector3(0, 0.8, 0), Color(0.85, 0.95, 1.0), 3.5, {"sparks": 70})
		if m.camera_rig != null:
			m.camera_rig.shake(0.35 if o == G.player or u == G.player else 0.1)
		var dmg: float = lvl_lerp(200.0, 350.0) + o.stats.bonus_ad + 0.6 * o.stats.ap
		for e in m.enemies_in_radius(o.team, pos, 3.5):
			proc(e, dmg, G.DmgType.MAGIC, "big_snowball")
			K.knockup(e, 0.75, o)
			K.slow(e, 0.2, 2.0, o)


class HolySnowball extends SnowAug:
	func _init() -> void:
		power = 2.0
		haste = 100.0
		description = "After using Mark's Dash, become invulnerable for 1.5 seconds on arrival. Mark's cooldown is reduced by the equivalent of 100 haste."

	func on_snowball_dash_arrive(_t) -> void:
		K.buff(owner, "holy_snowball", 1.5, {}, owner, {"name": "Holy Snowball", "cc": Buff.CC.INVULNERABLE})
		Vfx.shield_bubble(owner, Color(1.0, 0.95, 0.6), 1.5, 1.1)
