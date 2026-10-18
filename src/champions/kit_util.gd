class_name K
extends RefCounted
## Helper library for champion kits: missiles, areas, crowd control, buffs, dashes.
## Distances passed in League units unless the name ends with _m (meters).

# ===================================================================== missiles
## Linear skillshot. opts: width (units), color, size, pierce, max_hits, minions(bool), champions(bool),
## on_hit(Callable(missile, unit)), on_end(Callable(missile, pos)), visual(Node3D), height, accel, light
static func line_missile(ab: Ability, from: Vector3, dir: Vector3, speed: float, range_units: float, opts: Dictionary = {}) -> Missile:
	var o = ab.owner
	var mi := Missile.new()
	mi.ability = ab
	mi.setup_linear(o, from, dir, speed * G.U, range_units * G.U, opts.get("width", 80.0) * G.U)
	mi.pierce = opts.get("pierce", false)
	mi.max_hits = opts.get("max_hits", 1)
	mi.hits_minions = opts.get("minions", true)
	mi.hits_champions = opts.get("champions", true)
	mi.stop_on_champion = opts.get("stop_on_champion", false)
	mi.height = opts.get("height", 1.0)
	mi.accel = opts.get("accel", 0.0) * G.U
	if opts.has("max_speed"):
		mi.max_speed = opts.max_speed * G.U
	if opts.has("on_hit"):
		mi.on_hit = opts.on_hit
	if opts.has("on_end"):
		mi.on_end = opts.on_end
	if opts.has("on_move"):
		mi.on_move = opts.on_move
	var vis = opts.get("visual")
	if vis == null:
		vis = Vfx.orb(opts.get("color", Color(0.6, 0.8, 1.0)), opts.get("size", 0.45), opts.get("light", false))
	mi.visual = vis
	_lol_visual(mi, opts)
	o.match_ref.add_missile(mi, from)
	return mi


## opts "lol": League VFX system name for this missile's visual; "keep_visual": keep the kit visual as is.
static func _lol_visual(mi: Missile, opts: Dictionary) -> void:
	if opts.get("keep_visual", false):
		mi.custom["keep_visual"] = true
	var nm: String = opts.get("lol", "")
	if nm != "":
		var lv := LolVfx.make(nm, {"loop": true})
		if lv != null:
			if mi.visual != null and is_instance_valid(mi.visual) and mi.visual.get_parent() == null:
				mi.visual.queue_free()
			mi.visual = lv
			mi.custom["keep_visual"] = true


## Homing missile to a unit (cannot miss). on_hit(missile, unit).
static func homing_missile(ab: Ability, from: Vector3, target: Unit, speed: float, on_hit: Callable, opts: Dictionary = {}) -> Missile:
	var o = ab.owner
	var mi := Missile.new()
	mi.ability = ab
	mi.setup_homing(o, from, target, speed * G.U)
	mi.height = opts.get("height", 1.0)
	mi.on_hit = on_hit
	if opts.has("on_end"):
		mi.on_end = opts.on_end
	var vis = opts.get("visual")
	if vis == null:
		vis = Vfx.orb(opts.get("color", Color(0.6, 0.8, 1.0)), opts.get("size", 0.35), opts.get("light", false))
	mi.visual = vis
	_lol_visual(mi, opts)
	o.match_ref.add_missile(mi, from)
	return mi


## Lobbed projectile to a point; on_land(missile, pos).
static func arc_missile(ab: Ability, from: Vector3, to: Vector3, flight_time: float, on_land: Callable, opts: Dictionary = {}) -> Missile:
	var o = ab.owner
	var mi := Missile.new()
	mi.ability = ab
	mi.setup_arc(o, from, to, flight_time, opts.get("arc", 3.0))
	mi.height = opts.get("height", 1.0)
	mi.on_end = on_land
	var vis = opts.get("visual")
	if vis == null:
		vis = Vfx.orb(opts.get("color", Color(1.0, 0.6, 0.2)), opts.get("size", 0.5), opts.get("light", true))
	mi.visual = vis
	_lol_visual(mi, opts)
	o.match_ref.add_missile(mi, from)
	return mi


static func cast_pos(u: Unit, height: float = 1.0) -> Vector3:
	return u.global_position + Vector3(0, height, 0) + u.facing * u.radius * 0.6


# ===================================================================== areas
static func enemies_circle(ab: Ability, center: Vector3, radius_units: float, champs_only: bool = false) -> Array:
	return ab.owner.match_ref.enemies_in_radius(ab.owner.team, center, radius_units * G.U, champs_only)


static func enemies_line(ab: Ability, a: Vector3, b: Vector3, width_units: float, champs_only: bool = false) -> Array:
	return ab.owner.match_ref.units_in_line(ab.owner.team, a, b, width_units * G.U * 0.5, champs_only)


static func enemies_cone(ab: Ability, origin: Vector3, dir: Vector3, length_units: float, angle_deg: float, champs_only: bool = false) -> Array:
	return ab.owner.match_ref.units_in_cone(ab.owner.team, origin, dir, length_units * G.U, angle_deg, champs_only)


## Damage everything in a circle now. Returns hit units.
static func damage_circle(ab: Ability, center: Vector3, radius_units: float, amount: float, type: int, opts: Dictionary = {}) -> Array:
	var hit := enemies_circle(ab, center, radius_units, opts.get("champs_only", false))
	var o := {"is_aoe": true}
	o.merge(opts.get("dmg_opts", {}), true)
	for u in hit:
		var dmg := amount
		if u.kind == G.Kind.MINION and opts.has("minion_mult"):
			dmg *= opts.minion_mult
		ab.hit(u, dmg, type, o)
		if opts.has("each"):
			opts.each.call(u)
	return hit


## Telegraphed circle that triggers after `delay`. on_trigger(units: Array, pos: Vector3).
static func delayed_circle(ab: Ability, pos: Vector3, radius_units: float, delay: float, color: Color, on_trigger: Callable, show: bool = true) -> void:
	var m = ab.owner.match_ref
	if show:
		var g := Vfx.ground_circle(m, pos, radius_units * G.U, Color(color.r, color.g, color.b, 0.7), delay + 0.05, 0.18)
		var mat: ShaderMaterial = g.get_meta("mat")
		var tw := g.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("fill", v), 0.05, 0.45, delay)
	m.after(delay, func():
		if not is_instance_valid(ab.owner):
			return
		var hit := enemies_circle(ab, pos, radius_units)
		on_trigger.call(hit, pos))


# ===================================================================== crowd control
static func _cc(target: Unit, id: String, name: String, flags: int, duration: float, src) -> Buff:
	if target == null or target.dead or duration <= 0.0:
		return null
	var b := Buff.new(id, duration)
	b.display_name = name
	b.cc = flags
	b.is_debuff = true
	return target.add_buff(b, src)


static func stun(target: Unit, duration: float, src) -> Buff:
	var b := _cc(target, "stun", "Stunned", Buff.CC.STUN, duration, src)
	if b != null and b.vfx == null:
		b.vfx = Vfx.stun_stars(target, b.duration)
	return b


static func root(target: Unit, duration: float, src, color: Color = Color(1.0, 0.95, 0.5)) -> Buff:
	var b := _cc(target, "root", "Rooted", Buff.CC.ROOT, duration, src)
	if b != null and b.vfx == null:
		b.vfx = Vfx.aura(target, color, 0.9, b.duration, 0.08)
	return b


static func silence(target: Unit, duration: float, src) -> Buff:
	return _cc(target, "silence", "Silenced", Buff.CC.SILENCE, duration, src)


static func disarm(target: Unit, duration: float, src) -> Buff:
	return _cc(target, "disarm", "Disarmed", Buff.CC.DISARM, duration, src)


static func ground(target: Unit, duration: float, src) -> Buff:
	return _cc(target, "grounded", "Grounded", Buff.CC.GROUNDED, duration, src)


static func charm(target: Unit, duration: float, src: Unit, slow: float = 0.65) -> Buff:
	var b := _cc(target, "charm", "Charmed", Buff.CC.CHARM, duration, src)
	if b != null:
		b.forced_target = src
		b.stats = {"ms%": -slow}
		target.stats.mark_dirty()
		if b.vfx == null:
			b.vfx = Vfx.rising(target, Color(1.0, 0.45, 0.75), b.duration, 18, 0.5)
	return b


static func fear(target: Unit, duration: float, src: Unit, slow: float = 0.0) -> Buff:
	var b := _cc(target, "fear", "Feared", Buff.CC.FEAR, duration, src)
	if b != null:
		b.forced_target = src
		if slow > 0.0:
			b.stats = {"ms%": -slow}
	return b


static func taunt(target: Unit, duration: float, src: Unit) -> Buff:
	var b := _cc(target, "taunt", "Taunted", Buff.CC.TAUNT, duration, src)
	if b != null:
		b.forced_target = src
	return b


static func suppress(target: Unit, duration: float, src) -> Buff:
	return _cc(target, "suppress", "Suppressed", Buff.CC.SUPPRESS, duration, src)


static func sleep(target: Unit, duration: float, src) -> Buff:
	return _cc(target, "sleep", "Asleep", Buff.CC.SLEEP, duration, src)


static func knockup(target: Unit, duration: float, src) -> Buff:
	if target == null or target.dead:
		return null
	return target.knockup(duration, src)


## Movement slow (0..1). decays: slow fades over the duration.
static func slow(target: Unit, amount: float, duration: float, src, decays: bool = false, id: String = "") -> Buff:
	if target == null or target.dead:
		return null
	var b := Buff.new(id if id != "" else "slow_" + str(src.get_instance_id() if src != null else 0), duration)
	b.display_name = "Slowed"
	b.slow_amount = amount
	b.slow_decays = decays
	b.is_debuff = true
	b.stack_mode = Buff.Stack.REFRESH
	return target.add_buff(b, src)


## Generic timed stat buff (positive unless is_debuff).
static func buff(target: Unit, id: String, duration: float, stats: Dictionary, src = null, opts: Dictionary = {}) -> Buff:
	if target == null or target.dead:
		return null
	var b := Buff.new(id, duration)
	b.display_name = opts.get("name", id)
	b.stats = stats
	b.is_debuff = opts.get("debuff", false)
	b.icon = opts.get("icon", null)
	b.max_stacks = opts.get("max_stacks", 1)
	b.stack_mode = opts.get("stack_mode", Buff.Stack.REFRESH)
	b.stats_per_stack = opts.get("per_stack", {})
	b.hidden = opts.get("hidden", false)
	b.cc = opts.get("cc", 0)
	if opts.has("decay_ms"):
		b.slow_decays = false
	return target.add_buff(b, src if src != null else target)


## Decaying movement speed boost implemented as a buff whose ms% fades.
static func haste(target: Unit, amount: float, duration: float, src = null, decays: bool = true, id: String = "haste") -> Buff:
	var b := HasteBuff.new(id, duration)
	b.amount = amount
	b.decays = decays
	b.display_name = "Haste"
	return target.add_buff(b, src if src != null else target)


static func shield(src: Unit, target: Unit, amount: float, duration: float, color: Color = Color(0.9, 0.9, 1.0), sid: String = "") -> void:
	if target == null or target.dead:
		return
	Combat.shield(src, target, amount, duration, {"id": sid})
	Vfx.shield_bubble(target, color, minf(duration, 3.0), maxf(0.9, target.radius * 1.6))


static func grievous(target: Unit, duration: float, src, amount: float = 0.4) -> void:
	var b := Buff.new("grievous", duration)
	b.stats = {"_gw": amount}
	b.is_debuff = true
	b.display_name = "Grievous Wounds"
	target.add_buff(b, src)


# ===================================================================== damage-over-time
static func dot(ab: Ability, target: Unit, total: float, duration: float, type: int, id: String, interval: float = 0.5, tag: String = "burn") -> Buff:
	if target == null or target.dead:
		return null
	var ticks := maxf(1.0, round(duration / interval))
	var per := total / ticks
	var src = ab.owner
	var b := Buff.new(id, duration)
	b.display_name = id
	b.is_debuff = true
	b.tick_interval = interval
	b.on_interval = func(_bb):
		if is_instance_valid(src) and not target.dead:
			Combat.deal(src, target, per, type, {"is_dot": true, "is_spell": true, "ability": ab, "tag": tag})
	return target.add_buff(b, src)


# ===================================================================== tooltips
## Resolve @Value@ placeholders in a League tooltip with the ability's current numbers.
static func resolve_tooltip(ab: Ability, text: String) -> String:
	var re := RegEx.create_from_string("@([A-Za-z0-9_\\.]+)(\\*[\\-0-9\\.]+)?@")
	var out := text
	var guard := 0
	while guard < 40:
		guard += 1
		var mt := re.search(out)
		if mt == null:
			break
		var name := mt.get_string(1)
		var mult := 1.0
		if mt.get_string(2) != "":
			mult = float(mt.get_string(2).substr(1))
		var val = _tooltip_value(ab, name)
		var rep := "?"
		if val != null:
			var v: float = float(val) * mult
			rep = str(int(round(v))) if absf(v - round(v)) < 0.05 or absf(v) >= 20.0 else ("%.2f" % v).rstrip("0").rstrip(".")
		out = out.substr(0, mt.get_start()) + rep + out.substr(mt.get_end())
	return Hud._clean(out)


static func fnv1a(s: String) -> int:
	var h := 0x811C9DC5
	for c in s.to_lower().to_utf8_buffer():
		h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
	return h


static func _tooltip_value(ab: Ability, name: String):
	if ab.has_method("tooltip_value"):
		var v = ab.tooltip_value(name)
		if v != null:
			return v
	if ab.data.has(name):
		return ab.dv(name)
	var key := "#%08x" % fnv1a(name)
	var calc = ab.calcs.get(key, ab.calcs.get(name))
	if calc == null:
		return null
	return eval_formula(ab, str(calc))


## Evaluate an extracted calc formula string like "BaseDamage + 0.5*AP".
static func eval_formula(ab: Ability, f: String):
	if f.find(":") >= 0 or f.find("Effect") >= 0 or f.find("#") >= 0:
		return null
	var lvl_re := RegEx.create_from_string("lerpByLevel\\(([\\-0-9\\.]+)->([\\-0-9\\.]+)\\)")
	var s := f.replace("[as %]", "")
	var mt := lvl_re.search(s)
	while mt != null:
		var a := float(mt.get_string(1))
		var b := float(mt.get_string(2))
		s = s.substr(0, mt.get_start()) + "(%f + (%f) * (LEVEL - 1.0) / 17.0)" % [a, b - a] + s.substr(mt.get_end())
		mt = lvl_re.search(s)
	var names := PackedStringArray()
	var vals := []
	var o = ab.owner
	var stat_vars := {"AP": o.stats.ap, "AD": o.stats.ad, "bonusAD": o.stats.bonus_ad, "baseAD": o.stats.base_ad,
		"MaxHealth": o.stats.max_hp, "bonusMaxHealth": o.stats.max_hp - (o.stats.base.base_hp + Stats.growth(o.stats.base.hp_per_level, o.level)),
		"bonusCurrentHealth": o.stats.max_hp - (o.stats.base.base_hp + Stats.growth(o.stats.base.hp_per_level, o.level)),
		"Armor": o.stats.armor, "bonusArmor": o.stats.bonus_armor, "MR": o.stats.mr, "bonusMR": o.stats.bonus_mr,
		"AttackSpeed": o.stats.attack_speed, "bonusAttackSpeed": o.stats.bonus_as, "LEVEL": float(o.level),
		"CritChance": o.stats.crit_chance, "MoveSpeed": o.stats.move_speed, "bonusMoveSpeed": 0.0, "Lethality": o.stats.lethality,
		"MissingHealth": o.stats.max_hp - o.hp, "CurrentHealth": o.hp, "stat9": o.stats.crit_chance}
	for k in stat_vars:
		names.append(k)
		vals.append(stat_vars[k])
	for k in ab.data:
		if k is String and k.is_valid_identifier() and not stat_vars.has(k):
			names.append(k)
			vals.append(ab.dv(k))
	var e := Expression.new()
	if e.parse(s, names) != OK:
		return null
	var r = e.execute(vals, null, false)
	if e.has_execute_failed():
		return null
	return r


class HasteBuff extends Buff:
	var amount := 0.3
	var decays := true

	func get_stat_mods() -> Dictionary:
		var k := clampf(remaining / maxf(duration, 0.01), 0.0, 1.0) if decays else 1.0
		return {"ms%": amount * k}

	func on_tick(u, _dt: float) -> void:
		if decays:
			u.stats.mark_dirty()
