class_name Combat
extends RefCounted
## Damage, healing and shielding pipeline shared by every unit.

const ASSIST_WINDOW := 10.0


## Deal damage. opts keys map onto DamageInfo fields (is_attack, is_spell, is_aoe,
## is_dot, is_proc, is_crit, can_crit, ability, tag, no_vamp, no_hooks, show_number, is_pet).
static func deal(source, target, amount: float, type: int, opts: Dictionary = {}) -> DamageInfo:
	var info := DamageInfo.new(source, target, amount, type)
	for k in opts:
		info.set(k, opts[k])
	return apply(info)


## Nested damage events (procs triggering procs) are capped so chains can't explode exponentially.
const MAX_DEPTH := 8
static var depth := 0
static var _depth_warned := false


static func apply(info: DamageInfo) -> DamageInfo:
	if depth >= MAX_DEPTH:
		info.cancelled = true
		if not _depth_warned:
			_depth_warned = true
			push_warning("Combat: proc chain depth limit hit (%s -> %s, %s)" % [info.source.display_name if info.source != null and is_instance_valid(info.source) else "?", info.target.display_name if info.target != null and is_instance_valid(info.target) else "?", info.tag])
		return info
	depth += 1
	var r := _apply(info)
	depth -= 1
	return r


static func _apply(info: DamageInfo) -> DamageInfo:
	var target = info.target
	var source = info.source
	if G.debug_sites:
		G.crumb("deal %s -> %s %s" % [source.display_name if source != null and is_instance_valid(source) else "?", target.display_name if target != null and is_instance_valid(target) else "?", info.tag])
		G.ctx3 = "deal %s -> %s %s %.0f" % [source.display_name if source != null and is_instance_valid(source) else "?", target.display_name if target != null and is_instance_valid(target) else "?", info.tag, info.amount]
	if target == null or not is_instance_valid(target) or target.dead:
		info.cancelled = true
		return info
	if target.is_invulnerable():
		info.cancelled = true
		if info.show_number and target.match_ref != null:
			target.match_ref.fx_text(target, "Immune", Color(0.8, 0.8, 0.8), info)
		return info
	if source != null and not is_instance_valid(source):
		source = null
		info.source = null
	if not info.no_hooks:
		if source != null:
			for e in source.effects.duplicate():
				if G.debug_sites: G.crumb("pre_dealt " + str(e.id))
				e.on_pre_damage_dealt(info)
		for e in target.effects.duplicate():
			if G.debug_sites: G.crumb("pre_taken " + str(e.id))
			e.on_pre_damage_taken(info)
	if info.cancelled:
		return info
	# ability / item damage that can crit (augments flip can_crit on): 145% + bonus crit damage
	if info.can_crit and not info.is_crit and source != null and not info.is_attack:
		if G.rng.randf() < source.stats.crit_chance:
			info.is_crit = true
			var cm: float = info.crit_mult if info.crit_mult > 0.0 else 1.45 + (source.stats.crit_damage - Rules.CRIT_DAMAGE)
			info.amount *= cm
	var raw := (info.amount + info.flat_bonus) * info.mult
	if source != null:
		raw *= 1.0 + source.stats.dmg_amp
	raw *= 1.0 - target.stats.dmg_reduction
	if target.has_method("damage_taken_multiplier"):
		raw *= target.damage_taken_multiplier(source)
	if source != null and source.kind == G.Kind.CHAMPION and target.kind == G.Kind.CHAMPION:
		source.set_meta("last_hit_ally_champ", source.match_ref.time if source.match_ref != null else 0.0)
		# ARAM: reduced champion damage at very long range (not for DoTs / ultimates)
		if not info.is_dot and not (info.ability != null and info.ability.is_ult):
			var du := G.flat_dist(source.global_position, target.global_position) / G.U
			raw *= Rules.long_range_mult(du)
	var post := raw
	if info.type == G.DmgType.PHYSICAL:
		post = raw * resist_multiplier(target.stats.armor, source, true)
	elif info.type == G.DmgType.MAGIC:
		post = raw * resist_multiplier(target.stats.mr, source, false)
	post = maxf(post, 0.0)
	info.mitigated = post
	# shields
	var remaining: float = target.absorb_shields(post, info.type)
	info.absorbed = post - remaining
	info.final = remaining
	target.hp -= remaining
	if info.ability != null and not info.is_attack and source != null and is_instance_valid(source) and source.match_ref != null and source.match_ref.audio != null:
		source.match_ref.audio.spell_hit(source, info.ability, target)
	if info.ability != null and not info.is_attack and not info.is_dot:
		LolVfx.on_spell_hit(source, info.ability, target)
	target.on_damaged(info)
	if source != null:
		target.record_damage(source, post)
		source.damage_dealt_total += post
		if source.kind == G.Kind.CHAMPION and target.kind == G.Kind.CHAMPION:
			source.champion_damage_total += post
	# vamp
	if source != null and not info.no_vamp and not info.is_reflect and post > 0.0 and not source.dead:
		var vamp: float = source.stats.omnivamp
		if info.is_attack:
			vamp += source.stats.lifesteal
		if info.is_spell:
			vamp += source.stats.spell_vamp
		if info.is_pet:
			vamp *= 0.33
		if vamp > 0.0 and target.kind != G.Kind.TURRET and target.kind != G.Kind.INHIBITOR and target.kind != G.Kind.NEXUS:
			heal(source, source, post * vamp, {"is_vamp": true, "show": false})
	if target.match_ref != null and info.show_number:
		target.match_ref.fx_damage(info)
	if not info.no_hooks:
		if source != null:
			for e in source.effects.duplicate():
				if G.debug_sites: G.crumb("dealt " + str(e.id))
				e.on_damage_dealt(info)
		for e in target.effects.duplicate():
			if G.debug_sites: G.crumb("taken " + str(e.id))
			e.on_damage_taken(info)
	if target.hp <= 0.0 and not target.dead:
		var saved := false
		for e in target.effects.duplicate():
			if e.prevent_death(info):
				saved = true
				break
		if saved:
			target.hp = maxf(target.hp, 1.0)
		else:
			target.hp = 0.0
			info.killed = true
			target.die(source, info)
	return info


## Damage multiplier for a given armor/MR value with the source's penetration.
static func resist_multiplier(resist: float, source, physical: bool) -> float:
	var r := resist
	if source != null:
		if physical:
			if r > 0.0:
				r = r * (1.0 - source.stats.armor_pen_pct)
				r = maxf(0.0, r - source.lethality_flat())
		else:
			if r > 0.0:
				r = r * (1.0 - source.stats.magic_pen_pct)
				r = maxf(0.0, r - source.stats.magic_pen)
	if r >= 0.0:
		return 100.0 / (100.0 + r)
	return 2.0 - 100.0 / (100.0 - r)


## Heal target. Applies heal power of the source and grievous wounds on the target.
static func heal(source, target, amount: float, opts: Dictionary = {}) -> float:
	if target == null or not is_instance_valid(target) or target.dead or amount <= 0.0 or depth >= MAX_DEPTH:
		return 0.0
	depth += 1
	var r := _heal(source, target, amount, opts)
	depth -= 1
	return r


static func _heal(source, target, amount: float, opts: Dictionary) -> float:
	var amt := amount
	var is_vamp: bool = opts.get("is_vamp", false)
	if source != null and is_instance_valid(source) and not is_vamp:
		amt *= 1.0 + source.stats.heal_power
		for e in source.effects.duplicate():
			amt = e.modify_heal_shield_dealt(amt, target, false)
	for e in target.effects.duplicate():
		amt = e.modify_heal_received(amt, source)
	amt *= 1.0 - target.grievous_wounds()
	var before: float = target.hp
	target.hp = minf(target.stats.max_hp, target.hp + amt)
	var healed: float = target.hp - before
	if healed > 0.0:
		target.healing_received_total += healed
		if source != null and is_instance_valid(source):
			source.healing_done_total += healed
			if not is_vamp:
				for e in source.effects.duplicate():
					e.on_heal_dealt(target, healed)
		if opts.get("show", true) and target.match_ref != null and healed >= 5.0:
			target.match_ref.fx_heal(target, healed)
	return healed


static func shield(source, target, amount: float, duration: float, opts: Dictionary = {}) -> Dictionary:
	if target == null or not is_instance_valid(target) or target.dead or amount <= 0.0 or depth >= MAX_DEPTH:
		return {}
	depth += 1
	var r := _shield(source, target, amount, duration, opts)
	depth -= 1
	return r


static func _shield(source, target, amount: float, duration: float, opts: Dictionary) -> Dictionary:
	var amt := amount
	if source != null and is_instance_valid(source):
		amt *= 1.0 + source.stats.heal_power
		for e in source.effects.duplicate():
			amt = e.modify_heal_shield_dealt(amt, target, true)
	var s: Dictionary = target.add_shield(amt, duration, source, opts.get("type", -1), opts.get("decay", false), opts.get("id", ""))
	if source != null and is_instance_valid(source):
		for e in source.effects.duplicate():
			e.on_shield_dealt(target, amt)
	for e in target.effects.duplicate():
		e.on_shield_received(amt)
	return s
