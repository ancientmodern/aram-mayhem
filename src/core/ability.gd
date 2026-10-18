class_name Ability
extends RefCounted
## Base class for champion abilities and summoner spells.
## Subclasses override execute() (and optionally ai_consider()).

enum Target { NONE, UNIT, POINT, DIRECTION }
enum Ind { NONE, LINE, CIRCLE, CONE, RANGE }
enum Side { ENEMY, ALLY, ANY, ALLY_OR_SELF }

var owner = null                ## Champion
var slot := 0                   ## 0..3 = QWER, 4 = passive, 5/6 = summoners
var key := "Q"
var id := ""
var display_name := ""
var description := ""
var icon: Texture2D = null
var level := 0
var max_level := 5
var is_ult := false
var is_summoner := false
var cooldowns: Array = [10.0]   ## per rank (index = level-1)
var costs: Array = [0.0]
var cast_range := 600.0         ## League units (0 = self)
var target_type := Target.DIRECTION
var target_side := Side.ENEMY
var target_champions_only := false
var indicator := Ind.LINE
var ind_width := 120.0          ## League units (line width)
var ind_radius := 200.0         ## League units (circle radius)
var ind_angle := 45.0           ## degrees (cone)
var ind_length := 0.0           ## League units, override for line length (0 = cast_range)
var cast_time := 0.25
var face_target := true
var can_move_while_casting := false
var can_move_while_channeling := false
var uninterruptible := false
var anim := "spell1"
var anim_lock := 0.45
var cd := 0.0
var cd_total := 0.0
var max_charges := 0            ## >0 = ammo system
var charges := 0
var charge_cd := 0.0
var charge_timer := 0.0
var recast_window := 0.0        ## >0 while a recast is available
var recast_count := 0
var toggled := false
var data := {}                  ## authentic data values from game files
var calcs := {}
var no_cost_text := ""
var resets_attack := false
var cast_count := 0
var self_cast_ok := true        ## UNIT abilities targeting allies may self cast
var tooltip_raw := ""           ## League tooltip with @placeholders@


func _init(p_owner = null) -> void:
	owner = p_owner


# ---------------------------------------------------------------- data helpers
## Value from a per-rank array (index 0 = rank 1), or a scalar.
func rv(v) -> float:
	if v is Array:
		if v.is_empty():
			return 0.0
		return float(v[clampi(level - 1, 0, v.size() - 1)])
	return float(v)


## Authentic data value from game json (arrays are 7 long with index 0 = rank 0).
func dv(name: String, default: float = 0.0) -> float:
	if not data.has(name):
		return default
	var v = data[name]
	if v is Array:
		if v.is_empty():
			return default
		if v.size() >= 6:
			return float(v[clampi(level, 0, v.size() - 1)])
		return float(v[clampi(level - 1, 0, v.size() - 1)])
	return float(v)


func cost() -> float:
	return rv(costs)


func base_cooldown() -> float:
	return rv(cooldowns)


func range_m() -> float:
	return cast_range * G.U


func ap() -> float:
	return owner.stats.ap


func ad() -> float:
	return owner.stats.ad


func bonus_ad() -> float:
	return owner.stats.bonus_ad


# ---------------------------------------------------------------- state
func is_ready() -> bool:
	if level <= 0:
		return false
	if recast_window > 0.0:
		return true
	if max_charges > 0:
		return charges > 0
	return cd <= 0.0


func can_afford() -> bool:
	if recast_window > 0.0:
		return true
	return not owner.stats.uses_mana or owner.mana >= cost()


## Returns "" if castable, else a short reason.
func cast_block_reason() -> String:
	if owner.dead:
		return "dead"
	if level <= 0:
		return "not learned"
	if not is_ready():
		return "cooldown"
	if not can_afford():
		return "mana"
	if not owner.can_cast():
		return "cc"
	if (owner.cc & Buff.CC.GROUNDED) != 0 and is_dash():
		return "grounded"
	if not owner.casting.is_empty() and owner.casting.ability == self:
		return "casting"
	return extra_block_reason()


func extra_block_reason() -> String:
	return ""


func is_dash() -> bool:
	return false


func tick(dt: float) -> void:
	if cd > 0.0:
		cd = maxf(0.0, cd - dt)
	if max_charges > 0 and charges < max_charges:
		charge_timer -= dt
		if charge_timer <= 0.0:
			charges += 1
			charge_timer = owner.stats.cooldown(charge_cd, is_ult) if charges < max_charges else 0.0
	if recast_window > 0.0:
		recast_window -= dt
		if recast_window <= 0.0:
			recast_window = 0.0
			on_recast_expired()
	on_tick(dt)


func on_tick(_dt: float) -> void:
	pass


func on_recast_expired() -> void:
	start_cooldown()


func start_cooldown(override: float = -1.0) -> void:
	var base := base_cooldown() if override < 0.0 else override
	var c: float
	if is_summoner:
		c = base * 100.0 / (100.0 + owner.stats.summoner_haste)
	else:
		c = owner.stats.cooldown(base, is_ult, not is_ult)
	for e in owner.effects:
		c = e.modify_cooldown(self, c)
	cd = c
	cd_total = c


func reduce_cooldown(seconds: float) -> void:
	cd = maxf(0.0, cd - seconds)


func reduce_cooldown_pct(pct: float) -> void:
	cd = maxf(0.0, cd - cd * pct)


# ---------------------------------------------------------------- targeting
## Build target info from a world point (cursor) and an optional hovered unit.
func make_target(world_pos: Vector3, hovered = null) -> Dictionary:
	var o: Vector3 = owner.global_position
	var t := {"pos": world_pos, "dir": G.flat_dir(o, world_pos), "unit": null}
	if target_type == Target.UNIT:
		t.unit = hovered if valid_unit_target(hovered) else null
		if t.unit == null and target_side != Side.ENEMY and self_cast_ok:
			t.unit = owner
		if t.unit != null:
			t.pos = t.unit.global_position
	elif target_type == Target.POINT or target_type == Target.DIRECTION:
		var d := G.flat_dist(o, world_pos)
		var maxr := range_m() if target_type == Target.POINT else (ind_length if ind_length > 0.0 else cast_range) * G.U
		if d > maxr and maxr > 0.0 and clamp_point_to_range():
			t.pos = o + t.dir * maxr
	return t


func clamp_point_to_range() -> bool:
	return true


func valid_unit_target(u) -> bool:
	if u == null or not is_instance_valid(u) or u.dead:
		return false
	if target_champions_only and u.kind != G.Kind.CHAMPION:
		return false
	match target_side:
		Side.ENEMY:
			return u.team != owner.team and u.is_targetable_by(owner.team) and u.kind != G.Kind.TURRET \
					and u.kind != G.Kind.INHIBITOR and u.kind != G.Kind.NEXUS
		Side.ALLY:
			return u.team == owner.team and u != owner and not u.dead and u.kind in [G.Kind.CHAMPION, G.Kind.SUMMON]
		Side.ALLY_OR_SELF:
			return u.team == owner.team and not u.dead and u.kind in [G.Kind.CHAMPION, G.Kind.SUMMON]
		Side.ANY:
			return u.is_targetable_by(owner.team)
	return false


func target_still_valid(t: Dictionary) -> bool:
	if target_type == Target.UNIT:
		return valid_unit_target(t.get("unit"))
	return true


func target_position(t: Dictionary) -> Vector3:
	if t.get("unit") != null and is_instance_valid(t.unit):
		return t.unit.global_position
	return t.pos


func in_cast_range(t: Dictionary) -> bool:
	if target_type == Target.UNIT and t.get("unit") != null:
		var u = t.unit
		return G.flat_dist(owner.global_position, u.global_position) <= range_m() + owner.radius + u.radius
	if target_type == Target.POINT and not clamp_point_to_range():
		return G.flat_dist(owner.global_position, t.pos) <= range_m()
	return true


# ---------------------------------------------------------------- casting flow
## Entry point from controllers. Returns true if the cast started or was queued.
func try_cast(t: Dictionary) -> bool:
	var reason := cast_block_reason()
	if reason != "":
		if reason == "casting" or (reason == "cc" and false):
			return false
		owner.on_cast_failed(self, reason)
		return false
	if target_type == Target.UNIT and t.get("unit") == null:
		owner.on_cast_failed(self, "no target")
		return false
	if owner.windup_timer >= 0.0 and not cancels_windup():
		owner.cancel_windup()
	if not owner.casting.is_empty() or not owner.dash.is_empty():
		owner.queued_cast = {"ability": self, "target": t}
		return true
	if not in_cast_range(t):
		owner.pending_cast = {"ability": self, "target": t}
		owner._repath_timer = 0.0
		return true
	begin_cast(t)
	return true


func cancels_windup() -> bool:
	return false


## Pay costs, start cooldown, start cast windup (or execute immediately).
func begin_cast(t: Dictionary) -> void:
	var recasting := recast_window > 0.0
	if not recasting:
		if owner.stats.uses_mana:
			owner.mana -= cost()
		if max_charges > 0:
			if charges == max_charges:
				charge_timer = owner.stats.cooldown(charge_cd, is_ult)
			charges -= 1
			cd = 0.25
			cd_total = 0.25
		elif auto_cooldown():
			start_cooldown()
	cast_count += 1
	if face_target and t.has("pos"):
		owner.face_toward(t.pos, 100.0)
	if cast_time > 0.0:
		owner.casting = {"ability": self, "target": t, "t": cast_time, "total": cast_time}
		if not can_move_while_casting:
			owner.stop_moving()
	if anim != "":
		owner.play_spell_anim(anim, maxf(anim_lock, cast_time), anim_speed())
	if cast_time <= 0.0:
		execute(t)


func anim_speed() -> float:
	return 1.0


## Whether begin_cast starts the cooldown automatically.
func auto_cooldown() -> bool:
	return true


## Called after windup. Subclasses implement the effect and must call notify_cast().
func execute(t: Dictionary) -> void:
	notify_cast(t)


func notify_cast(t: Dictionary) -> void:
	if resets_attack:
		owner.reset_attack()
	for e in owner.effects.duplicate():
		e.on_ability_cast(self, t)
	if owner.has_method("on_ability_executed"):
		owner.on_ability_executed(self, t)


func start_channel(duration: float, extra: Dictionary = {}) -> void:
	var ch := {"ability": self, "t": duration, "total": duration}
	ch.merge(extra)
	owner.channel = ch


func channel_tick(_dt: float, _ch: Dictionary) -> void:
	pass


func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
	pass


# ---------------------------------------------------------------- helpers for kits
## Damage helper honoring ability flags.
func hit(target, amount: float, type: int = G.DmgType.MAGIC, opts: Dictionary = {}) -> DamageInfo:
	var o := {"is_spell": true, "ability": self}
	o.merge(opts, true)
	return Combat.deal(owner, target, amount, type, o)


func m() -> Node:
	return owner.match_ref


func enemies_in_radius(center: Vector3, r_units: float, champs_only: bool = false) -> Array:
	return owner.match_ref.enemies_in_radius(owner.team, center, r_units * G.U, champs_only)


func allies_in_radius(center: Vector3, r_units: float, champs_only: bool = true) -> Array:
	return owner.match_ref.allies_in_radius(owner.team, center, r_units * G.U, champs_only)


# ---------------------------------------------------------------- AI
## Bot hint. Return a target dictionary to cast, or {} to skip.
## `ctx` is provided by BotBrain (see bot_brain.gd).
func ai_consider(_ctx) -> Dictionary:
	return {}


func tooltip_text() -> String:
	if tooltip_raw != "":
		return K.resolve_tooltip(self, tooltip_raw)
	return description
