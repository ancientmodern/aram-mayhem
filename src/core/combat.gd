class_name Combat
extends RefCounted
## Damage, healing and shielding pipeline shared by every unit.

const ASSIST_WINDOW := 20.0   # [numbers] kill-bounty config AssistDurationOverride 20 s (map12.bin ARAM + Kiwi); was 10


## Deal damage. opts keys map onto DamageInfo fields (is_attack, is_spell, is_aoe,
## is_dot, is_proc, is_crit, can_crit, ability, tag, no_vamp, no_hooks, show_number, is_pet).
static func deal(source, target, amount: float, type: int, opts: Dictionary = {}) -> DamageInfo:
	var info := DamageInfo.new(source, target, amount, type)
	for k in opts:
		info.set(k, opts[k])
	return apply(info)


## Nested damage events (procs triggering procs) are capped so chains can't explode exponentially.
const MAX_DEPTH := 8
const HOOK_DEPTH := 3
const FRAME_BUDGET := 1500
static var frame_events := 0
static var depth := 0
static var _depth_warned := false


static func apply(info: DamageInfo) -> DamageInfo:
	if depth >= MAX_DEPTH:
		info.cancelled = true
		if not _depth_warned:
			_depth_warned = true
			push_warning("Combat: proc chain depth limit hit (%s -> %s, %s)" % [info.source.display_name if info.source != null and is_instance_valid(info.source) else "?", info.target.display_name if info.target != null and is_instance_valid(info.target) else "?", info.tag])
		return info
	# procs don't proc: past a shallow chain (or a per-frame budget) damage applies without triggering hooks,
	# otherwise item/augment procs branch exponentially (millions of events + floating texts)
	frame_events += 1
	if depth >= HOOK_DEPTH or frame_events > FRAME_BUDGET:
		info.no_hooks = true
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
	if source != null:
		raw *= _aram_damage_ratio(source, target, info)
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
		post = raw * resist_multiplier(target.stats.armor, source, true, target)
	elif info.type == G.DmgType.MAGIC:
		post = raw * resist_multiplier(target.stats.mr, source, false, target)
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
		var vamp := vamp_fraction(source, target, info)
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
## [numbers] League order: (armor reduction is already in `resist`), percent penetration, then flat (lethality), both
## ignored when the resist is <= 0; turrets have 30% armor penetration (wiki Turret, Ohmwrecker); penetration has no
## effect on an inhibitor's armor (wiki Inhibitor).
static func resist_multiplier(resist: float, source, physical: bool, target = null) -> float:
	var r := resist
	if source != null and not (target != null and target.kind == G.Kind.INHIBITOR):
		if physical:
			if r > 0.0:
				var pct: float = source.stats.armor_pen_pct
				if source.kind == G.Kind.TURRET:
					pct = 1.0 - (1.0 - pct) * (1.0 - Rules.TURRET_ARMOR_PEN)
				r = r * (1.0 - pct)
				r = maxf(0.0, r - source.lethality_flat())
		else:
			if r > 0.0:
				r = r * (1.0 - source.stats.magic_pen_pct)
				r = maxf(0.0, r - source.stats.magic_pen)
	if r >= 0.0:
		return 100.0 / (100.0 + r)
	return 2.0 - 100.0 / (100.0 - r)


## [numbers] League ARAM (Map12 GameModeConstants dr_* ratios + wiki ARAM): lane minions deal 50% to champions and to
## structures, champion damage to structures grows +0% -> +25% from 18:00 to 30:00 (melee champions with more AP than AD
## get at least +20%), area damage deals 75% to minions.
static func _aram_damage_ratio(source, target, info) -> float:
	var m := 1.0
	var tk: int = target.kind
	var is_struct := tk == G.Kind.TURRET or tk == G.Kind.INHIBITOR or tk == G.Kind.NEXUS
	match source.kind:
		G.Kind.MINION:
			if tk == G.Kind.CHAMPION:
				m *= Rules.UNIT_TO_HERO_DR
			elif is_struct:
				m *= Rules.UNIT_TO_BUILDING_DR
		G.Kind.CHAMPION:
			if is_struct:
				var t: float = source.match_ref.time if source.match_ref != null else 0.0
				var b := Rules.structure_bonus(t)
				# Howling Abyss aura: melee champions with more AP than AD deal +20% to structures (until the time bonus passes it)
				if source.stats.attack_range < 300.0 and source.stats.ap > source.stats.ad:
					b = maxf(b, Rules.MELEE_AP_STRUCT_BONUS)
				m *= 1.0 + b
			elif tk == G.Kind.MINION:
				if info.is_aoe:
					m *= Rules.AOE_VS_MINION
				# wiki ARAM: melee champions deal +20% to siege and super minions
				var mt: int = target.minion_type
				if source.stats.attack_range < 300.0 and (mt == Minion.Type.SIEGE or mt == Minion.Type.SUPER):
					m *= 1.2
	return m


## [numbers] Fraction of post-mitigation damage returned as healing (League Map12 GameModeConstants): omnivamp and spell
## vamp are x0.333 for AoE / pet / DoT damage and against minions or monsters; life steal is x0.33 for AoE / pet damage;
## the Howling Abyss aura cuts life steal and omnivamp healing against minions by 40% (wiki ARAM).
static func vamp_fraction(source, target, info) -> float:
	var vs_minion: bool = target.kind == G.Kind.MINION
	var third := 0.333
	var omni: float = source.stats.omnivamp
	if omni > 0.0 and (info.is_aoe or info.is_pet or info.is_dot or vs_minion):
		omni *= third
	var sv := 0.0
	if info.is_spell:
		sv = source.stats.spell_vamp
		if sv > 0.0 and (info.is_aoe or info.is_pet or info.is_dot or vs_minion):
			sv *= third
	var ls := 0.0
	if info.is_attack:
		ls = source.stats.lifesteal
		if ls > 0.0 and (info.is_aoe or info.is_pet):
			ls *= 0.33
		if ls > 0.0 and vs_minion:
			ls *= 0.6
	return omni + sv + ls


## Heal target. Applies heal power of the source and grievous wounds on the target.
static func heal(source, target, amount: float, opts: Dictionary = {}) -> float:
	if target == null or not is_instance_valid(target) or target.dead or amount <= 0.0 or depth >= MAX_DEPTH:
		return 0.0
	depth += 1
	if G.debug_sites: G.crumb("heal -> " + str(target.display_name))
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
	# ARAM: heals on others are halved (self-heals, vamp and relics are not)
	if not is_vamp and source != null and is_instance_valid(source) and source != target and source.kind == G.Kind.CHAMPION:
		amt *= Rules.ARAM_OUTGOING_HEAL
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
