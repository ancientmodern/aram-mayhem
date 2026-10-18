class_name Summoners
extends RefCounted
## Summoner spells available on the Howling Abyss (no Exhaust in Mayhem).

const ALL := ["Flash", "Mark", "Ghost", "Heal", "Barrier", "Cleanse", "Ignite", "Clarity"]


static func make(name: String, c) -> Ability:
	var a: Ability
	match name:
		"Flash": a = FlashSpell.new(c)
		"Mark": a = MarkSpell.new(c)
		"Ghost": a = GhostSpell.new(c)
		"Heal": a = HealSpell.new(c)
		"Barrier": a = BarrierSpell.new(c)
		"Cleanse": a = CleanseSpell.new(c)
		"Ignite": a = IgniteSpell.new(c)
		"Clarity": a = ClaritySpell.new(c)
		_: a = FlashSpell.new(c)
	a.is_summoner = true
	a.level = 1
	a.max_level = 1
	a.id = name
	a.icon = Assets.summoner_icon(name.to_lower())
	a.anim = ""
	return a


static func give_default(c, d: String = "Flash", f: String = "Mark") -> void:
	c.summoners[0] = make(d, c)
	c.summoners[0].slot = 5
	c.summoners[0].key = "D"
	c.summoners[1] = make(f, c)
	c.summoners[1].slot = 6
	c.summoners[1].key = "F"


static func set_spell(c, slot_index: int, name: String) -> void:
	var a := make(name, c)
	a.slot = 5 + slot_index
	a.key = "D" if slot_index == 0 else "F"
	c.summoners[slot_index] = a


## League particle systems for Flash / Barrier, extracted into data/vfx/shared.json by the vfx pipeline
## (tools/lol/extract_vfx.py). Candidate names in League's naming; the first one present is used, otherwise the
## procedural fallback. TODO(vfx): if the extracted names differ, add them to these lists.
const FLASH_DEPART_VFX := ["Global_SS_Flash", "Summoner_Flash", "Global_SS_Flash_01"]
const FLASH_ARRIVE_VFX := ["Global_SS_Flash_02", "Summoner_Flash_Arrival", "Global_SS_Flash_Arrive"]
const BARRIER_VFX := ["Global_SS_Barrier", "Summoner_Barrier", "Global_SS_Barrier_Shield"]


static func lol_vfx_name(candidates: Array) -> String:
	for n in candidates:
		if LolVfx.has(n):
			return n
	return ""


class FlashSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Flash"
		description = "Teleports your champion a short distance toward your cursor's location."
		cooldowns = [300.0]
		cast_range = 400.0
		target_type = Target.POINT
		indicator = Ind.NONE
		cast_time = 0.0
		face_target = true

	func cancels_windup() -> bool:
		return true

	func execute(t: Dictionary) -> void:
		var o: Vector3 = owner.global_position
		var d := minf(G.flat_dist(o, t.pos), range_m())
		var dest: Vector3 = o + G.flat_dir(o, t.pos) * d
		var m = owner.match_ref
		dest = m.nav.clamp_walkable(o, dest)
		if not m.nav.is_walkable(dest):
			dest = m.nav.nearest_walkable(dest)
		var fdir := G.flat_dir(o, t.pos)
		var dep := Summoners.lol_vfx_name(Summoners.FLASH_DEPART_VFX)
		if dep == "" or LolVfx.spawn(m, dep, o, {"dir": fdir}) == null:
			Vfx.burst(m, o + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.4), 0.9, {"ring": false, "sparks": 16})
		owner.teleport(dest)
		owner.cancel_windup()
		owner.face_toward(o + fdir * 10.0, 100.0)
		var arr := Summoners.lol_vfx_name(Summoners.FLASH_ARRIVE_VFX)
		if arr == "" or LolVfx.attach(owner, arr, {"dir": fdir}) == null:
			Vfx.burst(m, dest + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.4), 0.9, {"ring": false, "sparks": 16})
		for e in owner.effects.duplicate():
			e.on_dash(o, dest)
			e.on_summoner_cast(self)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return ctx.flash_decision(self)


class MarkSpell extends Ability:
	var marked = null
	var tag_fx = null
	var mark_time := 0.0

	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Mark"
		description = "Throw a snowball. On hit, deals true damage and you can recast to dash to the target."
		cooldowns = [80.0]
		cast_range = 1600.0
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		cast_time = 0.0

	func is_dash() -> bool:
		return recast_window > 0.0

	func damage() -> float:
		var base: float = 10.0 + 5.0 * owner.level
		for e in owner.effects.duplicate():
			if e.has_method("snowball_damage_mult"):
				base *= e.snowball_damage_mult()
		return base

	## The mark ends early when the marked unit dies or becomes untargetable (no dash target left).
	func on_tick(_dt: float) -> void:
		if recast_window > 0.0 and (marked == null or not is_instance_valid(marked) or marked.dead or not marked.is_targetable_by(owner.team)):
			recast_window = 0.0
			on_recast_expired()

	func execute(t: Dictionary) -> void:
		var m = owner.match_ref
		if recast_window > 0.0 and (marked == null or not is_instance_valid(marked) or marked.dead):
			# recast but the target is gone: the mark is spent (it used to throw a free second snowball)
			recast_window = 0.0
			on_recast_expired()
			return
		if recast_window > 0.0 and marked != null and is_instance_valid(marked) and not marked.dead:
			recast_window = 0.0
			var tgt = marked
			marked = null
			if tag_fx != null and is_instance_valid(tag_fx):
				tag_fx.stop()
			var dash_fx := LolVfx.attach(owner, "Summoner_Snowball_Dash", {"loop": true, "dir": G.flat_dir(owner.global_position, tgt.global_position)})
			# the dash can be cut short (knockback / stun clears it without on_arrive): never leave the trail looping
			var dfx_ref := weakref(dash_fx) if dash_fx != null else null
			if dfx_ref != null:
				m.after(G.flat_dist(owner.global_position, tgt.global_position) / 18.0 + 0.3, func():
					K.kill_fx(dfx_ref.get_ref(), 0.3))
			LolVfx.spawn(m, "Summoner_Snowball_Dash_Cast", owner.global_position)
			owner.start_dash(tgt.global_position, {"speed": 18.0, "on_arrive": func(_u):
				for e in owner.effects.duplicate():
					if e.has_method("on_snowball_dash_arrive"):
						e.on_snowball_dash_arrive(tgt)
				if dash_fx != null and is_instance_valid(dash_fx):
					dash_fx.stop()
				if LolVfx.spawn(m, "Summoner_Snowball_Dash_Arrival", owner.global_position) == null:
					Vfx.burst(m, owner.global_position + Vector3(0, 0.5, 0), Color(0.8, 0.95, 1.0), 1.2)})
			start_cooldown()
			notify_cast(t)
			return
		var mi := Missile.new()
		var from: Vector3 = owner.global_position + Vector3(0, 1.0, 0)
		mi.setup_linear(owner, from, t.dir, 13.0, range_m(), 0.6)
		mi.hits_minions = true
		var ally_view: bool = G.player == null or owner.team == G.player.team
		var lv := LolVfx.make("Summoner_Snowball_Mis" if ally_view else "Summoner_Snowball_Mis_Enemy", {"loop": true})
		mi.visual = lv if lv != null else Vfx.orb(Color(0.85, 0.95, 1.0), 0.45, false)
		mi.custom["keep_visual"] = true
		mi.on_hit = func(_m, u):
			hit(u, damage(), G.DmgType.TRUE, {"is_spell": false, "is_proc": true, "tag": "snowball"})
			marked = u
			recast_window = 3.0
			cd = 0.0
			if LolVfx.spawn(m, "Summoner_Snowball_Explosion", u.global_position + Vector3(0, 1.0, 0)) == null:
				Vfx.burst(m, u.global_position + Vector3(0, 1.0, 0), Color(0.85, 0.95, 1.0), 1.0, {"ring": false})
			if tag_fx != null and is_instance_valid(tag_fx):
				tag_fx.stop()
			tag_fx = LolVfx.attach(u, "Summoner_Snowball_Tagged", {"loop": true})
			for e in owner.effects.duplicate():
				if e.has_method("on_snowball_hit"):
					e.on_snowball_hit(u)
		for e in owner.effects.duplicate():
			if e.has_method("modify_snowball"):
				e.modify_snowball(mi)
		m.add_missile(mi, from)
		for e in owner.effects.duplicate():
			e.on_summoner_cast(self)
		notify_cast(t)

	func auto_cooldown() -> bool:
		return true

	func on_recast_expired() -> void:
		marked = null
		if tag_fx != null and is_instance_valid(tag_fx):
			tag_fx.stop()
		tag_fx = null
		start_cooldown()

	func ai_consider(ctx) -> Dictionary:
		return ctx.mark_decision(self)


class GhostSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Ghost"
		description = "Gain Ghosted and 24-48% Movement Speed for 10 seconds."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var b := K.FxBuff.new("ghost", 10.0)
		b.kill_fade = 0.3
		b.display_name = "Ghost"
		b.cc = Buff.CC.GHOSTED
		b.stats = {"ms%": 0.24 + 0.24 * (owner.level - 1) / 17.0}
		b.icon = icon
		owner.add_buff(b, owner)
		b.vfx = LolVfx.attach(owner, "Global_Haste", {"loop": true})
		if b.vfx == null:
			Vfx.rising(owner, Color(0.6, 0.85, 1.0), 1.0, 30)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {} if not ctx.wants_speed() else {"pos": owner.global_position}


class HealSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Heal"
		description = "Restore 90-345 Health and grant 30% Movement Speed to you and an ally."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 850.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var amt: float = 90.0 + 15.0 * (owner.level - 1)
		var targets := [owner]
		var best = null
		var best_r := 2.0
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, range_m()):
			if a != owner and a.hp_ratio() < best_r:
				best_r = a.hp_ratio()
				best = a
		if best != null:
			targets.append(best)
		for u in targets:
			Combat.heal(owner, u, amt)
			# League Heal: 30% move speed for 2 s
			var b := Buff.new("heal_ms", 2.0)
			b.stats = {"ms%": 0.3}
			b.display_name = "Heal"
			u.add_buff(b, owner)
			if LolVfx.attach(u, "Item_Redemption_Hit_Heal") == null:
				Vfx.rising(u, Color(0.4, 1.0, 0.45), 0.5, 30)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.hp_ratio() < 0.25 and ctx.in_danger() else {}


class BarrierSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Barrier"
		description = "Gain a 105-411 Shield for 2.5 seconds."
		cooldowns = [180.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var amt: float = 105.0 + 18.0 * (owner.level - 1)
		var sh: Dictionary = Combat.shield(owner, owner, amt, 2.5)
		# the bubble disappears when the barrier breaks (it used to stay the full 2.5 s)
		var nm := Summoners.lol_vfx_name(Summoners.BARRIER_VFX)
		var fx: Node = LolVfx.attach(owner, nm, {"loop": true}) if nm != "" else null
		if fx == null:
			fx = Vfx.shield_bubble(owner, Color(1.0, 0.9, 0.5), 2.5, 1.1)
		K.track_shield_fx(owner, sh, fx)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.hp_ratio() < 0.25 and ctx.in_danger() else {}


class CleanseSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Cleanse"
		description = "Remove all disables and summoner debuffs and gain 65% Tenacity for 3 seconds."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		owner.cleanse()
		# League Cleanse also removes summoner spell debuffs (Ignite and its Grievous Wounds)
		owner.remove_buffs_by_id("ignite")
		for gb in owner.buffs.duplicate():
			if gb.id == "grievous" and gb.has_meta("ignite"):
				owner.remove_buff(gb)
		var b := Buff.new("cleanse", 3.0)
		b.stats = {"tenacity": 0.65}
		owner.add_buff(b, owner)
		if LolVfx.attach(owner, "Jade_Summoner_Cleanse") == null:
			Vfx.rising(owner, Color(0.7, 0.9, 1.0), 0.4, 30)
		notify_cast(t)

	func ai_consider(_ctx) -> Dictionary:
		return {"pos": owner.global_position} if (owner.cc & (Buff.CC.STUN | Buff.CC.ROOT | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP)) != 0 else {}


class IgniteSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Ignite"
		description = "Ignites target enemy champion, dealing 70-410 true damage over 5 seconds and applying Grievous Wounds."
		cooldowns = [180.0]
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var u = t.unit
		var total: float = 70.0 + 20.0 * (owner.level - 1)
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var src = owner
		var b := K.FxBuff.new("ignite", 5.0)
		b.is_debuff = true
		b.display_name = "Ignite"
		b.tick_interval = 1.0
		b.on_interval = func(bb):
			if is_instance_valid(src) and is_instance_valid(bb.owner) and not bb.owner.dead:
				Combat.deal(src, bb.owner, total / 5.0, G.DmgType.TRUE, {"is_dot": true, "is_proc": true, "tag": "burn"})
		# a second Ignite refreshes the first one: only the live buff may own the burning effect (the effect used
		# to be attached to the discarded new buff and burned forever)
		var got: Buff = u.add_buff(b, owner)
		var gw := Buff.new("grievous", 5.0)   # the core reads Grievous Wounds by this id
		gw.set_meta("ignite", true)
		gw.stats = {"_gw": 0.4}
		gw.is_debuff = true
		gw.display_name = "Grievous Wounds"
		u.add_buff(gw, owner)
		if got != null and (got.vfx == null or not is_instance_valid(got.vfx)):
			got.vfx = LolVfx.attach(u, "Global_SS_Ignite", {"loop": true})
			if got.vfx == null:
				got.vfx = Vfx.rising(u, Color(1.0, 0.5, 0.15), 5.0, 25, 0.4)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return ctx.ignite_decision(self)


class ClaritySpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Clarity"
		description = "Restores 50% of your champion's maximum Mana. Also restores allies for 25% of their maximum Mana."
		cooldowns = [240.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		owner.mana = minf(owner.stats.max_mana, owner.mana + owner.stats.max_mana * 0.5)
		for a in owner.match_ref.allies_in_radius(owner.team, owner.global_position, range_m()):
			if a != owner:
				a.mana = minf(a.stats.max_mana, a.mana + a.stats.max_mana * 0.25)
		Vfx.ring(owner.match_ref, owner.global_position, Color(0.4, 0.6, 1.0), 6.0, 0.6)
		notify_cast(t)

	func ai_consider(_ctx) -> Dictionary:
		return {"pos": owner.global_position} if owner.stats.max_mana > 0.0 and owner.mana < owner.stats.max_mana * 0.25 else {}
