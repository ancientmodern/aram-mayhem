class_name ItemFx
extends RefCounted
## Item passives and actives.

static var _makers := {}


static func _reg() -> void:
	if not _makers.is_empty():
		return
	_makers = {
		"GuardianHorn": func(): return GuardianHorn.new(), "Spellblade": func(): return Spellblade.new(),
		"Cleave": func(): return Cleave.new(), "Immolate": func(): return Immolate.new(), "Steelcaps": func(): return Steelcaps.new(),
		"Kraken": func(): return Kraken.new(), "Botrk": func(): return Botrk.new(), "Guinsoo": func(): return Guinsoo.new(),
		"Cleaver": func(): return Cleaver.new(), "Steraks": func(): return Steraks.new(), "Bloodthirster": func(): return Bloodthirster.new(),
		"TitanicCleave": func(): return TitanicCleave.new(), "DeathsDance": func(): return DeathsDance.new(),
		"Statikk": func(): return Statikk.new(), "Runaans": func(): return Runaans.new(), "Collector": func(): return Collector.new(),
		"Reminder": func(): return Reminder.new(), "Navori": func(): return Navori.new(), "Youmuu": func(): return Youmuu.new(),
		"Eclipse": func(): return Eclipse.new(), "Shojin": func(): return Shojin.new(), "Stridebreaker": func(): return Stridebreaker.new(),
		"Maw": func(): return Maw.new(), "Shieldbow": func(): return Shieldbow.new(), "WitsEnd": func(): return WitsEnd.new(),
		"Luden": func(): return Luden.new(), "Zhonya": func(): return Zhonya.new(), "Liandry": func(): return Liandry.new(),
		"LichBane": func(): return Spellblade.new(), "Nashor": func(): return Nashor.new(), "Rylai": func(): return Rylai.new(),
		"Shadowflame": func(): return Shadowflame.new(), "Banshee": func(): return Banshee.new(), "Riftmaker": func(): return Riftmaker.new(),
		"Archangel": func(): return Archangel.new(), "Rocketbelt": func(): return Rocketbelt.new(), "Heartsteel": func(): return Heartsteel.new(),
		"Thornmail": func(): return Thornmail.new(), "Warmogs": func(): return Warmogs.new(), "Visage": func(): return Visage.new(),
		"Randuin": func(): return Randuin.new(), "Atma": func(): return Atma.new(), "Blossom": func(): return Blossom.new(),
		"Locket": func(): return Locket.new(), "Redemption": func(): return Redemption.new(), "Anvil": func(): return Item.new(),
	}


static func has_class(n: String) -> bool:
	_reg()
	return _makers.has(n)


static func make(n: String) -> Item:
	_reg()
	return _makers[n].call()


static func in_combat(u) -> bool:
	return u.match_ref != null and u.match_ref.time - u.last_combat_time < 3.0


static func bonus_hp(u) -> float:
	return u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level))


class GuardianHorn extends Item:
	func on_pre_damage_taken(info) -> void:
		if info.is_attack and info.source != null and info.source.kind == G.Kind.CHAMPION:
			info.flat_bonus -= 12.0


class Spellblade extends Item:
	## Sheen family. Damage depends on which item this is.
	var ready := false
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func _best() -> bool:
		# only the strongest spellblade item procs
		var rank := {3057: 0, 3078: 2, 3508: 1, 3100: 2}
		for e in owner.items:
			if e != self and e is Spellblade and rank.get(e.item_id, 0) > rank.get(item_id, 0):
				return false
		return true

	func on_ability_cast(ab, _t) -> void:
		if not ab.is_summoner and cd <= 0.0 and _best():
			ready = true

	func on_attack_hit(t, info) -> void:
		if not ready or info == null or not info.is_attack:
			return
		ready = false
		cd = 1.5
		var o = owner
		match item_id:
			3078:
				proc(t, o.stats.base_ad * 2.0, G.DmgType.PHYSICAL, "spellblade")
			3508:
				proc(t, o.stats.base_ad + 0.4 * o.stats.bonus_ad, G.DmgType.PHYSICAL, "spellblade")
				o.mana = minf(o.stats.max_mana, o.mana + (o.stats.max_mana - o.mana) * 0.06)
			3100:
				proc(t, 0.75 * o.stats.base_ad + 0.45 * o.stats.ap, G.DmgType.MAGIC, "spellblade")
			_:
				proc(t, o.stats.base_ad, G.DmgType.PHYSICAL, "spellblade")
		Vfx.hit_spark(o.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(0.6, 0.8, 1.0) if item_id != 3100 else Color(0.7, 0.4, 1.0), 0.8)

	func on_attack_launch(_t) -> void:
		if item_id == 3078:
			K.haste(owner, 0.2, 2.0, owner, false, "triforce_ms")


class Cleave extends Item:
	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or not is_melee() and item_id == 3077 and false:
			return
		if info.on_hit_mult < 1.0:
			return
		var o = owner
		var dmg: float = o.stats.ad * (0.4 if is_melee() else 0.2)
		for e in o.match_ref.enemies_in_radius(o.team, t.global_position, 3.5):
			if e != t:
				Combat.deal(o, e, dmg, G.DmgType.PHYSICAL, {"is_proc": true, "is_aoe": true, "tag": "cleave"})
		Vfx.ring(o.match_ref, t.global_position, Color(0.9, 0.7, 0.4), 2.0, 0.25, 0.25, 0.0)


class TitanicCleave extends Item:
	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		var o = owner
		var dmg: float = o.stats.max_hp * (0.01 if is_melee() else 0.0075)
		proc(t, dmg, G.DmgType.PHYSICAL, "titanic")
		for e in o.match_ref.units_in_cone(o.team, t.global_position, G.flat_dir(o.global_position, t.global_position), 4.5, 70.0):
			if e != t:
				Combat.deal(o, e, dmg * 2.0, G.DmgType.PHYSICAL, {"is_proc": true, "is_aoe": true, "tag": "titanic"})


class Immolate extends Item:
	var acc := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if u.dead or not ItemFx.in_combat(u):
			return
		# only one immolate source applies (the strongest)
		for e in u.items:
			if e != self and e is Immolate and e.item_id == 3068 and item_id != 3068:
				return
		acc += dt
		if acc < 1.0:
			return
		acc = 0.0
		var dmg: float = (20.0 if item_id == 3068 else 12.0) + 0.01 * ItemFx.bonus_hp(u)
		for e in u.match_ref.enemies_in_radius(u.team, u.global_position, 3.25):
			Combat.deal(u, e, dmg * (1.5 if e.kind == G.Kind.MINION else 1.0), G.DmgType.MAGIC, {"is_proc": true, "is_dot": true, "tag": "burn", "show_number": e.kind == G.Kind.CHAMPION})


class Steelcaps extends Item:
	func on_pre_damage_taken(info) -> void:
		if info.is_attack:
			info.mult *= 0.9


class Kraken extends Item:
	var count := 0

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		count += 1
		if count < 3:
			return
		count = 0
		var dmg: float = lvl_lerp(150.0, 200.0) * (1.0 + 0.75 * (1.0 - t.hp_ratio()))
		proc(t, dmg, G.DmgType.PHYSICAL, "kraken")
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1.0, 0), Color(0.3, 0.8, 0.9), 0.9, {"ring": false, "sparks": 14, "light": false})


class Botrk extends Item:
	var hits := {}

	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		var pct := 0.09 if is_melee() else 0.06
		var dmg: float = t.hp * pct * mult
		if t.kind == G.Kind.MINION:
			dmg = minf(dmg, 100.0)
		proc(t, dmg, G.DmgType.PHYSICAL, "botrk")
		if t.kind == G.Kind.CHAMPION:
			var n: int = hits.get(t, 0) + 1
			hits[t] = n
			if n % 3 == 0:
				K.slow(t, 0.3, 1.0, owner)


class Guinsoo extends Item:
	var count := 0

	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		proc(t, 30.0 * mult, G.DmgType.MAGIC, "guinsoo")
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		var b: Buff = owner.find_buff("guinsoo")
		if b == null:
			K.buff(owner, "guinsoo", 3.0, {}, owner, {"name": "Seething Strike", "max_stacks": 4, "stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"as": 0.08}})
		else:
			b.stacks = mini(4, b.stacks + 1)
			b.remaining = 3.0
			owner.stats.mark_dirty()
			if b.stacks >= 4:
				count += 1
				if count >= 3:
					count = 0
					owner.trigger_on_hit(t, info, 0.999, self)


class Cleaver extends Item:
	func on_damage_dealt(info) -> void:
		if info.type != G.DmgType.PHYSICAL or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var t = info.target
		var b: Buff = t.find_buff("carve", owner)
		if b == null:
			b = Buff.new("carve", 6.0)
			b.display_name = "Carve"
			b.is_debuff = true
			b.max_stacks = 5
			b.stack_mode = Buff.Stack.ADD_STACK
			b.stats_per_stack = {"armor%": -0.06}
			t.add_buff(b, owner)
		else:
			b.stacks = mini(5, b.stacks + 1)
			b.remaining = 6.0
			t.stats.mark_dirty()


class Steraks extends Item:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_taken(_info) -> void:
		if cd > 0.0 or owner.dead or owner.hp_ratio() > 0.3:
			return
		cd = 60.0
		Combat.shield(owner, owner, ItemFx.bonus_hp(owner) * 0.6, 4.0, {"decay": true, "id": "steraks"})
		Vfx.shield_bubble(owner, Color(1.0, 0.7, 0.3), 1.5, 1.1)


class Bloodthirster extends Item:
	func on_damage_dealt(info) -> void:
		if not info.is_attack or owner.hp < owner.stats.max_hp - 1.0:
			return
		var over: float = info.mitigated * owner.stats.lifesteal
		var cap: float = lvl_lerp(165.0, 315.0)
		var cur: float = 0.0
		for s in owner.shields:
			if s.id == "ichor":
				cur = s.amount
		var amt := minf(cap, cur + over)
		if amt > 1.0:
			owner.add_shield(amt, 25.0, owner, -1, true, "ichor")


class DeathsDance extends Item:
	func on_pre_damage_taken(info) -> void:
		if info.is_dot and info.tag == "deathsdance":
			return
		var pct := 0.3 if is_melee() else 0.15
		if info.amount <= 0.0 or info.type == G.DmgType.TRUE and info.tag == "deathsdance":
			return
		var delayed: float = info.amount * pct
		info.amount -= delayed
		var src = info.source
		var t = owner
		var typ: int = info.type
		var b := Buff.new("deaths_dance", 3.0)
		b.stack_mode = Buff.Stack.INDEPENDENT
		b.hidden = true
		b.tick_interval = 0.5
		b.on_interval = func(_x):
			Combat.deal(src if is_instance_valid(src) else null, t, delayed / 6.0, typ, {"is_dot": true, "no_hooks": true, "tag": "deathsdance", "show_number": false})
		owner.add_buff(b, owner)

	func on_takedown(_v) -> void:
		owner.remove_buffs_by_id("deaths_dance")
		Combat.heal(owner, owner, 1.25 * owner.stats.bonus_ad)


class Statikk extends Item:
	var energy := 0.0
	var last_pos := Vector3.INF

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		if last_pos != Vector3.INF:
			energy = minf(100.0, energy + G.flat_dist(u.global_position, last_pos) * 1.2)
		last_pos = u.global_position

	func on_attack_launch(_t) -> void:
		energy = minf(100.0, energy + 6.0)

	func on_attack_hit(t, info) -> void:
		if energy < 100.0 or info == null or not info.is_attack:
			return
		energy = 0.0
		var o = owner
		var m = o.match_ref
		var dmg: float = lvl_lerp(60.0, 150.0)
		var hit := {}
		var cur = t
		var prev: Vector3 = o.global_position + Vector3(0, 1.2, 0)
		for i in 6:
			if cur == null:
				break
			hit[cur] = true
			Vfx.beam(m, prev, cur.global_position + Vector3(0, 1.0, 0), Color(0.6, 0.85, 1.0), 0.07, 0.2)
			proc(cur, dmg * (2.0 if cur.kind == G.Kind.MINION else 1.0), G.DmgType.MAGIC, "statikk")
			prev = cur.global_position + Vector3(0, 1.0, 0)
			var nxt = null
			var bd := 6.0
			for e in m.enemies_in_radius(o.team, cur.global_position, 6.0):
				if not hit.has(e):
					var d: float = G.flat_dist(e.global_position, cur.global_position)
					if d < bd:
						bd = d
						nxt = e
			cur = nxt


class Runaans extends Item:
	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0 or info.tag == "runaans":
			return
		var o = owner
		var n := 0
		for e in o.match_ref.enemies_in_radius(o.team, o.global_position, o.attack_range_m() + 1.5):
			if e == t or n >= 2:
				continue
			n += 1
			var from: Vector3 = o.global_position + Vector3(0, 1.2, 0)
			var mi := Missile.new()
			mi.setup_homing(o, from, e, 20.0)
			mi.visual = Vfx.orb(Color(0.8, 0.95, 0.8), 0.25, false)
			var self_ref := self
			var crit: bool = info.is_crit
			mi.on_hit = func(_m, u):
				var d: float = o.stats.ad * 0.55 * (o.stats.crit_damage if crit else 1.0)
				var inf := Combat.deal(o, u, d, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "runaans", "is_crit": crit})
				o.trigger_on_hit(u, inf, 1.0, self_ref)
			o.match_ref.add_missile(mi, from)


class Collector extends Item:
	func on_damage_dealt(info) -> void:
		var t = info.target
		if t != null and t.kind == G.Kind.CHAMPION and not t.dead and t.hp_ratio() < 0.05 and info.tag != "collector":
			Combat.deal(owner, t, t.hp + 10.0, G.DmgType.TRUE, {"is_proc": true, "tag": "collector", "no_hooks": true})

	func on_kill(v) -> void:
		if v.kind == G.Kind.CHAMPION:
			owner.add_gold(25.0, v)


class Reminder extends Item:
	func on_damage_dealt(info) -> void:
		if info.type == G.DmgType.PHYSICAL and info.target != null and info.target.kind == G.Kind.CHAMPION:
			K.grievous(info.target, 3.0, owner)


class Navori extends Item:
	func on_attack_hit(_t, info) -> void:
		if info == null or not info.is_attack:
			return
		for i in 3:
			var ab = owner.abilities[i]
			if ab != null and ab.cd > 0.0:
				ab.reduce_cooldown_pct(0.15)


class Youmuu extends Item:
	func _init() -> void:
		active_cd = 45.0

	func use_active(_p: Vector3, _h) -> bool:
		K.buff(owner, "youmuu", 6.0, {"ms%": 0.2}, owner, {"name": "Wraith Step", "cc": Buff.CC.GHOSTED})
		Vfx.rising(owner, Color(0.6, 0.3, 0.9), 1.0, 30)
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" or (ctx.mode == "retreat" and ctx.in_danger())


class Eclipse extends Item:
	var hits := {}
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		var t = info.target
		if cd > 0.0 or t == null or t.kind != G.Kind.CHAMPION or info.is_dot or info.tag == "eclipse":
			return
		var now_t: float = owner.match_ref.time
		var last: float = hits.get(t, -10.0)
		if now_t - last > 0.1 and now_t - last < 2.0:
			cd = 6.0
			hits.erase(t)
			proc(t, t.stats.max_hp * 0.06, G.DmgType.PHYSICAL, "eclipse")
			Combat.shield(owner, owner, 160.0 + 0.4 * owner.stats.bonus_ad, 2.0)
			Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1, 0), Color(0.95, 0.85, 0.6), 1.0, {"ring": false})
		else:
			hits[t] = now_t


class Shojin extends Item:
	func on_pre_damage_dealt(info) -> void:
		if info.is_spell:
			var b: Buff = owner.find_buff("shojin")
			if b != null:
				info.mult *= 1.0 + 0.03 * b.stacks

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var b: Buff = owner.find_buff("shojin")
		if b == null:
			K.buff(owner, "shojin", 6.0, {}, owner, {"name": "Focused Will", "max_stacks": 4, "stack_mode": Buff.Stack.ADD_STACK})
		else:
			b.stacks = mini(4, b.stacks + 1)
			b.remaining = 6.0


class Stridebreaker extends Item:
	func _init() -> void:
		active_cd = 15.0

	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		Vfx.ring(o.match_ref, o.global_position, Color(1.0, 0.6, 0.3), 4.5, 0.35, 0.2, 0.15)
		for e in o.match_ref.enemies_in_radius(o.team, o.global_position, 4.5):
			proc(e, o.stats.ad * 0.8, G.DmgType.PHYSICAL, "stridebreaker")
			K.slow(e, 0.35, 2.0, o, true)
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.count_enemies_near(owner.global_position, 4.0) >= 1


class Maw extends Item:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_taken(info) -> void:
		if cd > 0.0 or info.type != G.DmgType.MAGIC or owner.hp_ratio() > 0.3 or owner.dead:
			return
		cd = 90.0
		Combat.shield(owner, owner, 200.0 + 2.25 * owner.stats.bonus_ad, 2.5, {"type": G.DmgType.MAGIC})
		Vfx.shield_bubble(owner, Color(0.6, 0.5, 1.0), 2.5, 1.1)


class Shieldbow extends Item:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_taken(_info) -> void:
		if cd > 0.0 or owner.hp_ratio() > 0.3 or owner.dead:
			return
		cd = 90.0
		Combat.shield(owner, owner, lvl_lerp(320.0, 720.0), 3.0)
		Vfx.shield_bubble(owner, Color(1.0, 0.8, 0.4), 3.0, 1.1)


class WitsEnd extends Item:
	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		proc(t, lvl_lerp(15.0, 80.0) * mult, G.DmgType.MAGIC, "witsend")


class Luden extends Item:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		if cd > 0.0 or not info.is_spell or info.target == null or info.target.kind == G.Kind.TURRET:
			return
		cd = 12.0
		var o = owner
		var targets: Array = o.match_ref.enemies_in_radius(o.team, info.target.global_position, 6.0)
		targets.sort_custom(func(a, b): return (0 if a.kind == G.Kind.CHAMPION else 1) < (0 if b.kind == G.Kind.CHAMPION else 1))
		if targets.is_empty():
			return
		var per: float = 50.0 + 0.1 * o.stats.ap
		for i in 6:
			var tgt = targets[i % targets.size()]
			var from: Vector3 = o.global_position + Vector3(0, 1.5, 0)
			var mi := Missile.new()
			mi.setup_homing(o, from, tgt, 14.0 + i)
			mi.visual = Vfx.orb(Color(0.45, 0.6, 1.0), 0.28, false)
			var self_ref := self
			mi.on_hit = func(_m, u): self_ref.proc(u, per, G.DmgType.MAGIC, "luden")
			o.match_ref.add_missile(mi, from)


class Zhonya extends Item:
	func _init() -> void:
		active_cd = 120.0

	func use_active(_p: Vector3, _h) -> bool:
		var o = owner
		var b := K.buff(o, "zhonya", 2.5, {}, o, {"name": "Stasis", "cc": Buff.CC.STASIS})
		o.cancel_windup()
		var fx := Vfx.shield_bubble(o, Color(1.0, 0.85, 0.35), 2.5, 1.2)
		for mat in o.materials:
			pass
		return true

	func ai_should_activate(ctx) -> bool:
		return owner.hp_ratio() < 0.2 and ctx.in_danger()


class Liandry extends Item:
	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.is_dot or info.target == null or info.target.kind == G.Kind.TURRET:
			return
		var t = info.target
		var src = owner
		var b := Buff.new("liandry", 3.0)
		b.display_name = "Torment"
		b.is_debuff = true
		b.tick_interval = 0.5
		b.on_interval = func(_x):
			if is_instance_valid(src) and not t.dead:
				Combat.deal(src, t, minf(t.stats.max_hp * 0.01, 120.0), G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "burn", "show_number": false})
		t.add_buff(b, owner)

	func on_pre_damage_dealt(info) -> void:
		if info.target != null and info.target.kind == G.Kind.CHAMPION and ItemFx.in_combat(owner):
			info.mult *= 1.04


class Nashor extends Item:
	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		proc(t, (15.0 + 0.15 * owner.stats.ap) * mult, G.DmgType.MAGIC, "nashor")


class Rylai extends Item:
	func on_damage_dealt(info) -> void:
		if info.is_spell and info.target != null and not info.is_dot and info.target.kind != G.Kind.TURRET:
			K.slow(info.target, 0.3, 1.0, owner, false, "rylai")


class Shadowflame extends Item:
	func on_pre_damage_dealt(info) -> void:
		if info.target != null and info.target.kind == G.Kind.CHAMPION and info.type != G.DmgType.PHYSICAL and info.target.hp_ratio() < 0.4:
			info.mult *= 1.2


class Banshee extends Item:
	var cd := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		cd = maxf(0.0, cd - dt)

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or not info.is_spell or info.source == null or info.source.kind != G.Kind.CHAMPION or info.is_dot:
			return
		cd = 40.0
		info.cancelled = true
		Vfx.shield_bubble(owner, Color(0.7, 0.5, 1.0), 0.5, 1.1)


class Riftmaker extends Item:
	var combat_t := 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		combat_t = minf(4.0, combat_t + dt) if ItemFx.in_combat(u) else 0.0

	func on_pre_damage_dealt(info) -> void:
		if info.target != null and info.target.kind == G.Kind.CHAMPION:
			info.mult *= 1.0 + 0.02 * combat_t


class Archangel extends Item:
	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			d["ap"] = d.get("ap", 0.0) + owner.stats.max_mana * 0.01
		return d


class Rocketbelt extends Item:
	func _init() -> void:
		active_cd = 40.0

	func use_active(p: Vector3, _h) -> bool:
		var o = owner
		var dir := G.flat_dir(o.global_position, p)
		o.start_dash(o.global_position + dir * 2.75, {"speed": 18.0})
		for i in 7:
			var ang := deg_to_rad(-30.0 + i * 10.0)
			var d := dir.rotated(Vector3.UP, ang)
			var mi := Missile.new()
			mi.setup_linear(o, o.global_position + Vector3(0, 1, 0), d, 16.0, 6.0, 0.4)
			mi.visual = Vfx.orb(Color(0.4, 0.7, 1.0), 0.3, false)
			var self_ref := self
			mi.on_hit = func(_m, u): self_ref.proc(u, 100.0 + 0.1 * o.stats.ap, G.DmgType.MAGIC, "rocketbelt")
			o.match_ref.add_missile(mi, o.global_position + Vector3(0, 1, 0))
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" and ctx.focus != null and G.flat_dist(owner.global_position, ctx.focus.global_position) < 6.0


class Heartsteel extends Item:
	var cds := {}
	var gained := 0.0

	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		d["hp"] = d.get("hp", 0.0) + gained
		d["size"] = minf(0.3, gained / 3000.0)
		return d

	func on_attack_hit(t, info) -> void:
		if t.kind != G.Kind.CHAMPION or info == null or not info.is_attack:
			return
		var now_t: float = owner.match_ref.time
		if now_t - cds.get(t, -100.0) < 30.0:
			return
		cds[t] = now_t
		var dmg: float = 70.0 + 0.06 * ItemFx.bonus_hp(owner)
		proc(t, dmg, G.DmgType.PHYSICAL, "heartsteel")
		var mult := 1.0
		for e in owner.effects.duplicate():
			if e.has_method("heartsteel_mult"):
				mult *= e.heartsteel_mult()
		gained += dmg * 0.1 * mult
		refresh_stats()
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1, 0), Color(0.9, 0.2, 0.3), 1.4, {"sparks": 20})


class Thornmail extends Item:
	func on_damage_taken(info) -> void:
		if info.is_attack and info.source != null and is_instance_valid(info.source) and info.source.kind != G.Kind.TURRET:
			Combat.deal(owner, info.source, 10.0 + 0.1 * owner.stats.bonus_armor, G.DmgType.MAGIC, {"is_proc": true, "is_reflect": true, "no_hooks": true, "tag": "thorns", "show_number": false})
			if info.source.kind == G.Kind.CHAMPION:
				K.grievous(info.source, 3.0, owner)


class Warmogs extends Item:
	var idle := 0.0

	func on_damage_taken(_i) -> void:
		idle = 0.0

	func on_tick(u, dt: float) -> void:
		super.on_tick(u, dt)
		idle += dt
		if idle > 6.0 and ItemFx.bonus_hp(u) >= 1500.0 and u.hp < u.stats.max_hp:
			u.hp = minf(u.stats.max_hp, u.hp + u.stats.max_hp * 0.03 * dt)


class Visage extends Item:
	func modify_heal_received(amount: float, _h) -> float:
		return amount * 1.25


class Randuin extends Item:
	func _init() -> void:
		active_cd = 60.0

	func on_pre_damage_taken(info) -> void:
		if info.is_crit:
			info.mult *= 0.7

	func use_active(_p: Vector3, _h) -> bool:
		Vfx.ring(owner.match_ref, owner.global_position, Color(0.8, 0.8, 0.9), 5.0, 0.4)
		for e in owner.match_ref.enemies_in_radius(owner.team, owner.global_position, 5.0):
			K.slow(e, 0.7, 2.0, owner)
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.count_enemies_near(owner.global_position, 4.5) >= 2


class Atma extends Item:
	func get_stat_mods() -> Dictionary:
		var d := stats.duplicate()
		if owner != null:
			d["crit"] = d.get("crit", 0.0) + clampf(ItemFx.bonus_hp(owner) / 3000.0, 0.0, 1.0) * 0.3
		return d


class Blossom extends Item:
	func on_attack_hit(_t, info) -> void:
		if info == null or not info.is_attack:
			return
		var best = owner
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, 8.0):
			if a.hp_ratio() < best.hp_ratio():
				best = a
		Combat.heal(owner, best, 15.0 + 0.15 * owner.stats.ap)


class Locket extends Item:
	func _init() -> void:
		active_cd = 90.0

	func use_active(_p: Vector3, _h) -> bool:
		var amt: float = 200.0 + 20.0 * owner.level
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, 8.5):
			K.shield(owner, a, amt, 2.5, Color(1.0, 0.85, 0.5))
		return true

	func ai_should_activate(ctx) -> bool:
		return ctx.mode == "fight" and ctx.count_enemies_near(owner.global_position, 8.0) >= 2


class Redemption extends Item:
	func _init() -> void:
		active_cd = 90.0

	func use_active(p: Vector3, _h) -> bool:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = p if G.flat_dist(p, o.global_position) < 55.0 else o.global_position
		Vfx.ground_circle(m, pos, 5.5, Color(1.0, 0.95, 0.6, 0.8), 2.05, 0.2)
		m.after(2.0, func():
			Vfx.beam(m, pos + Vector3(0, 14, 0), pos, Color(1.0, 0.95, 0.6), 3.0, 0.6)
			for a in m.allies_in_radius(o.team, pos, 5.5):
				Combat.heal(o, a, 200.0 + 15.0 * o.level)
			for e in m.enemies_in_radius(o.team, pos, 5.5, true):
				Combat.deal(o, e, e.stats.max_hp * 0.1, G.DmgType.TRUE, {"is_proc": true, "tag": "redemption"}))
		return true

	func ai_should_activate(ctx) -> bool:
		var a = ctx.lowest_ally(10.0, 0.4)
		return a != null and ctx.in_danger() or (a != null and ctx.mode == "fight")
