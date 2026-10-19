extends Node
## [timing] Headless check: in-engine cast times, missile speeds and basic-attack windups vs the League bins.
## Expected values come from data/timing/<champ>.json (tools/lol/extract_timing.py: raw bin fields, effective cast time =
## mCastTime / spellCastTime / castFrame/30, missile speeds from mMissileSpec.movementComponent) plus the EXPECT table
## below (compiled-script timing the bins do not hold: wiki values, each with its source).
## Usage: godot --headless --path . --fixed-fps 60 -- --champ=Jinx --harness=res://src/debug/timing_test.gd
## Output: "TIME <champ> <what> k=v ..." measurement lines, "TIMING PASS|FAIL <name> <detail>", final "TIMING DONE <champ> passes=N fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var dummies: Array = []
var spot := Vector3.ZERO
var passes := 0
var fails := 0
var T := {}            ## data/timing/<champ>.json
var G_JSON := {}       ## data/champions/<champ>_game.json
var atk_events: Array = []   ## [time, kind] from the attack tracker

const TOL := 0.04      ## s (2.4 frames at 60 fps)
const SPEED_TOL := 0.04   ## relative

## champion -> slot -> {cast, ms, ms_max, ms_min, dash}
##   cast    expected cast time (s): the effective bin value (mCastTime > spellCastTime > castFrame/30) where the wiki lists a
##           cast time, 0.0 where the wiki says "none" (instant / scripted: toggles, buffs, empowered attacks, Yi / Garen /
##           Sona / Malphite W,R ...), "script:jinxw" = 0.6 - 0.08 x bonus AS (min 0.4: JinxWMissile mCastTime 0.6, data values
##           JinxLowEndWCastTime 0.4 / JinxWASpeedCastTimeScalarPerHundrethSecond 0.08)
##   ms      initial missile speed (u/s) of the first missile the cast spawns (mMissileSpec.movementComponent, NOT the legacy
##           missileSpeed field); ms_max / ms_min peak / floor of accelerating missiles; dash = dash duration (s)
## Sources: bins in Champions/<X>.wad.client (data/timing/<x>.json) + wiki cast times (checked for all 14 champions).
const EXPECT := {
	"Ahri": {"Q": {"cast": 0.25, "ms": 2500.0, "ms_min": 400.0}, "W": {"cast": 0.0}, "E": {"cast": 0.25, "ms": 1550.0}, "R": {"cast": 0.0}},
	"Annie": {"Q": {"cast": 0.25, "ms": 1400.0}, "W": {"cast": 0.25}, "E": {"cast": 0.0}, "R": {"cast": 0.25}},
	"Darius": {"Q": {"cast": 0.0}, "W": {"cast": 0.0}, "E": {"cast": 0.25}, "R": {"cast": 0.0, "dash": 0.3667}},
	"Ezreal": {"Q": {"cast": 0.25, "ms": 2000.0}, "W": {"cast": 0.25, "ms": 1700.0}, "E": {"cast": 0.25}, "R": {"cast": 1.0, "ms": 2000.0}},
	"Garen": {"Q": {"cast": 0.0}, "W": {"cast": 0.0}, "E": {"cast": 0.0}, "R": {"cast": 0.435}},
	"Jinx": {"Q": {"cast": 0.0}, "W": {"cast": "script:jinxw", "ms": 3300.0}, "E": {"cast": 0.25}, "R": {"cast": 0.6, "ms": 1700.0, "ms_max": 2200.0, "dist": 22.0}},
	"Leona": {"Q": {"cast": 0.0}, "W": {"cast": 0.0}, "E": {"cast": 0.25, "ms": 2000.0}, "R": {"cast": 0.25}},
	"Lux": {"Q": {"cast": 0.25, "ms": 1200.0}, "W": {"cast": 0.25, "ms": 2200.0, "ms_min": 500.0, "acc": -2300.0}, "E": {"cast": 0.25, "ms": 1200.0}, "R": {"cast": 1.0}},
	"Malphite": {"Q": {"cast": 0.25, "ms": 1200.0}, "W": {"cast": 0.0}, "E": {"cast": 0.2419}, "R": {"cast": 0.0}},
	"MasterYi": {"Q": {"cast": 0.0}, "W": {"cast": 0.0}, "E": {"cast": 0.0}, "R": {"cast": 0.0}},
	"MissFortune": {"W": {"cast": 0.0}, "E": {"cast": 0.25}, "R": {"cast": 0.001}},
	"Sona": {"Q": {"cast": 0.0}, "W": {"cast": 0.0}, "E": {"cast": 0.0}, "R": {"cast": 0.25, "ms": 2400.0}},
	"Veigar": {"Q": {"cast": 0.25, "ms": 2200.0}, "W": {"cast": 0.25}, "E": {"cast": 0.25}, "R": {"cast": 0.25, "ms": 500.0, "acc": 4000.0}},
	"Yasuo": {"Q": {"cast": "script:yasuoq"}, "W": {"cast": 0.013}, "E": {"cast": 0.0}, "R": {"cast": 0.0}},
}


class AtkTracker extends Effect:
	var log: Array = []
	var t = null

	func _init() -> void:
		id = "harness_tracker"
		hidden = true

	func on_damage_dealt(info) -> void:
		if info.is_attack and t != null:
			log.append(t.m.time)


func _ready() -> void:
	_run()


func _frame() -> void:
	await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _qwait(s: float) -> void:
	var t0: float = m.time
	while m.time - t0 < s:
		_quiet()
		await _frame()


var attack_phase := false


func _quiet() -> void:
	for u in [c] + dummies:
		if u.dead:
			continue
		if u == c:
			# no idle auto attacks while probing spells (League auto-acquires), except during the attack probe
			if not attack_phase and c.attack_target != null and c.windup_timer < 0.0 and c.cmd != Unit.Cmd.ATTACK:
				c.attack_target = null
		elif u.attack_target != null:
			u.issue_move(u.global_position)


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TIMING %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


func _near(a: float, b: float, tol: float = TOL) -> bool:
	return absf(a - b) <= tol


func _near_rel(a: float, b: float) -> bool:
	return absf(a - b) <= maxf(absf(b) * SPEED_TOL, 5.0)


# ===================================================================== arena
func _setup() -> void:
	m = G.match
	c = G.player
	T = JSON.parse_string(FileAccess.get_file_as_string("res://data/timing/%s.json" % c.alias.to_lower()))
	G_JSON = JSON.parse_string(FileAccess.get_file_as_string("res://data/champions/%s_game.json" % c.alias.to_lower()))
	if c.augments_pending > 0 and m.has_method("get_offer"):
		m.get_offer(c)
		m.choose_augment(c, 0)
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION or u.kind == G.Kind.SUMMON:
			m.remove_unit(u)
	spot = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	for ch in m.champions:
		if ch == c:
			continue
		ch.controller = null
		ch.is_bot = false
		ch.teleport(ch.spawn_point)
		ch.issue_move(ch.spawn_point)
	for ch in m.champions:
		if ch.team != c.team and dummies.size() < 2:
			dummies.append(ch)
	c.gain_xp(1.0e6)
	for i in 30:
		if not c.level_ability(3):
			for s in [0, 1, 2]:
				if c.level_ability(s):
					break
	for d in dummies:
		var b := Buff.new("harness_disarm", 1.0)
		b.permanent = true
		b.hidden = true
		b.cc = Buff.CC.DISARM
		b.cleansable = false
		d.add_buff(b, d)
		for e in d.effects.duplicate():
			if e.id != "mayhem_aura" and not e.id.begins_with("harness"):
				d.remove_effect(e)
	_reset(5.0)


func _reset(dist: float) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	c.teleport(spot)
	c.issue_move(spot)
	c.face_toward(spot + fwd, 1000.0)
	c.stop_moving()
	for i in dummies.size():
		var d: Champion = dummies[i]
		if d.dead:
			d.respawn()
		var p: Vector3 = spot + fwd * (dist + i * 1.2) + side * (0.0 if i == 0 else 1.0)
		d.teleport(m.nav.nearest_walkable(p))
		d.issue_move(d.global_position)
		d.hp = d.stats.max_hp
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana


# ===================================================================== probes
## Cast slot `slot` at dummies[0] and record the cast time, movement lock, missiles (initial / peak speed) and channel.
func _probe_slot(slot: int, dist: float, extra_time: float = 1.2) -> Dictionary:
	_reset(dist)
	for mi in m.missiles:   # leftovers of the previous probe (Lux W return, Ahri Q return ...) must not be measured
		if is_instance_valid(mi) and mi.source == c:
			mi.alive = false
			mi.queue_free()
	await _qwait(0.2)
	var ab: Ability = c.abilities[slot]
	ab.cd = 0.0
	if ab.max_charges > 0:
		ab.charges = ab.max_charges
	c.mana = c.stats.max_mana
	var d: Champion = dummies[0]
	var tgt := ab.make_target(d.global_position, d)
	var seen := {}
	var res := {"slot": slot, "key": "QWER"[slot], "cast_total": 0.0, "exec_t": -1.0, "moved_in_cast": 0.0, "channel": 0.0,
			"dash": 0.0, "missiles": []}
	var p0: Vector3 = c.global_position
	var t0: float = m.time
	res["bonus_as"] = c.stats.bonus_as
	var ok := ab.try_cast(tgt)
	res["ok"] = ok
	if not c.casting.is_empty():
		res["cast_total"] = float(c.casting.total)
	res["cd_after"] = ab.cd
	# a move order during the windup must neither move her nor cancel the cast
	var far := c.global_position + c.facing * -6.0
	if not c.casting.is_empty():
		c.issue_move(far)
	var was_casting := not c.casting.is_empty()
	var pmove_ref: Vector3 = c.global_position
	var t_end: float = m.time + extra_time + float(res.cast_total)
	var exec_seen := not was_casting
	if exec_seen:
		res["exec_t"] = 0.0
	while m.time < t_end:
		await _frame()
		_quiet()
		if not exec_seen and c.casting.is_empty():
			exec_seen = true
			res["exec_t"] = m.time - t0
			res["moved_in_cast"] = G.flat_dist(pmove_ref, c.global_position)
		for mi in m.missiles:
			if not is_instance_valid(mi) or mi.is_attack or mi.source != c:
				continue
			var mid: int = mi.get_instance_id()   # never key a dictionary by objects that get freed
			if not seen.has(mid):
				seen[mid] = {"t": m.time - t0, "v0": mi.speed / G.U, "pos0": mi.global_position, "tpos": m.time, "vmax": mi.speed / G.U,
						"vmin": mi.speed / G.U, "accel": mi.accel / G.U, "mode": mi.mode, "w": mi.width / G.U, "meas": -1.0}
			var rec: Dictionary = seen[mid]
			rec.vmax = maxf(rec.vmax, mi.speed / G.U)
			rec.vmin = minf(rec.vmin, mi.speed / G.U)
			if rec.meas < 0.0 and m.time - rec.tpos >= 0.1 and rec.mode == Missile.Mode.LINEAR:
				rec.meas = G.flat_dist(rec.pos0, mi.global_position) / G.U / (m.time - rec.tpos)
		if not c.channel.is_empty() and res.channel == 0.0:
			res["channel"] = float(c.channel.total)
		if not c.dash.is_empty() and res.dash == 0.0:
			res["dash"] = float(c.dash.duration)
	for k in seen.keys():
		res.missiles.append(seen[k])
	res.missiles.sort_custom(func(a, b): return a.t < b.t)
	res["moved_total"] = G.flat_dist(p0, c.global_position)
	return res


func _fmt(r: Dictionary) -> String:
	var ms := []
	for x in r.missiles:
		ms.append("[t=%.2f v0=%.0f vmax=%.0f vmin=%.0f acc=%.0f meas=%.0f w=%.0f]" % [x.t, x.v0, x.vmax, x.vmin, x.accel, x.meas, x.w])
	return "cast_total=%.3f exec=%.3f moved_in_cast=%.2f channel=%.2f dash=%.2f cd=%.1f missiles=%d %s" % [
			r.cast_total, r.exec_t, r.moved_in_cast, r.channel, r.dash, r.cd_after, r.missiles.size(), " ".join(ms)]


## Expected cast time of a slot from the bin (effective value of the slot's spell, with a few scripted cases).
func _expected_cast(key: String, bonus: float) -> Variant:
	var ex: Dictionary = EXPECT.get(c.alias, {}).get(key, {})
	if ex.has("cast"):
		var v = ex.cast
		if v is String and v == "script:jinxw":
			return maxf(0.4, 0.6 - 0.08 * bonus)
		if v is String and v == "script:yasuoq":
			# wiki: thrust 0.35 -> 0.175 with bonus AS (floor where the cooldown floor is, 111.3% bonus AS; linear between)
			return 0.35 - 0.175 * clampf(maxf(0.0, bonus) / 1.113, 0.0, 1.0)
		return v
	return null


func _probe_attack() -> void:
	_reset(4.0 if c.attack_range_m() > 3.0 else 1.6)
	await _qwait(0.2)
	var tr := AtkTracker.new()
	tr.t = self
	c.add_effect(tr)
	var d: Champion = dummies[0]
	var dis := Buff.new("harness_disarm_c", 30.0)
	dis.hidden = true
	dis.cc = Buff.CC.DISARM
	dis.cleansable = false
	c.add_buff(dis, c)
	c.cancel_windup()
	c.attack_target = null
	c.cmd = Unit.Cmd.IDLE
	var wt := 0.0
	while c.attack_timer > 0.0 and wt < 4.0:
		await _frame()
		wt += 1.0 / 60.0
	c.attack_timer = 0.0
	c.remove_buff(dis)
	attack_phase = true
	var cnt0 := c.attack_count
	c.issue_attack(d)
	var t_start := -1.0
	var wind := -1.0
	var v0 := -1.0
	var vmeas := -1.0
	var t_launch := -1.0
	var pos0 := Vector3.ZERO
	var tpos := 0.0
	var seen_mi: Missile = null
	var t_hit := -1.0
	var period := 0.0
	var t_end: float = m.time + 3.0
	var dbg := 0
	while m.time < t_end:
		await _frame()
		dbg += 1
		if dbg % 10 == 1 and t_start < 0.0 and OS.get_cmdline_user_args().has("--dbg"):
			print("DBG t=%.3f end=%.3f f=%d cmd=%s atk_timer=%.2f windup=%.2f cnt=%d/%d moving=%s tgt_ok=%s" % [m.time, t_end, dbg, str(c.cmd), c.attack_timer, c.windup_timer, c.attack_count, cnt0, str(c.moving), str(c.attack_valid(c.attack_target))])
		if t_start < 0.0 and c.attack_count > cnt0:
			t_start = m.time
			wind = c.windup_timer
			period = c.stats.attack_period()
		if t_start >= 0.0 and seen_mi == null:
			for mi in m.missiles:
				if is_instance_valid(mi) and mi.is_attack and mi.source == c:
					seen_mi = mi
					t_launch = m.time
					v0 = mi.speed / G.U
					pos0 = mi.global_position
					tpos = m.time
		if seen_mi != null and is_instance_valid(seen_mi) and vmeas < 0.0 and m.time - tpos >= 0.1:
			vmeas = G.flat_dist(pos0, seen_mi.global_position) / G.U / (m.time - tpos)
		if not tr.log.is_empty() and t_hit < 0.0:
			t_hit = tr.log[0]
		if t_hit >= 0.0 and (seen_mi == null or not is_instance_valid(seen_mi) or t_launch >= 0.0):
			break
	c.remove_effect(tr)
	attack_phase = false
	if t_start < 0.0:
		print("TIME %s attack never started: cmd=%s dist=%.2f range=%.2f can_attack=%s atk_timer=%.2f windup=%.2f casting=%s channel=%s in_range=%s hold=%s" % [c.alias, str(c.cmd), G.flat_dist(c.global_position, d.global_position), c.attack_range_m(), str(c.can_attack()), c.attack_timer, c.windup_timer, str(not c.casting.is_empty()), str(not c.channel.is_empty()), str(c.in_attack_range(d)), str(c.attack_valid(c.attack_target))])
	c.issue_stop()
	var melee: bool = c.attack_missile_speed <= 0.0
	var bin_melee: bool = float(T.attack.attackRange) <= 350.0
	var win_meas := (t_hit if melee else t_launch) - t_start
	print("TIME %s attack period=%.3f windup_timer0=%.3f windup_measured=%.3f windup_pct=%.4f mod=%.2f missile_v0=%.0f meas=%.0f" % [
			c.alias, period, wind, win_meas, c.windup_pct, c.windup_mod, v0, vmeas])
	# expected windup: League formula from the bin
	var a: Dictionary = T.attack
	var as_total: float = c.stats.attack_speed
	var per: float = 1.0 / as_total
	var pct: float = float(a.windupPct)
	var w := per * pct
	var ratio: float = float(a.get("castOffsetRatio", 1.0)) if a.get("castOffsetRatio") != null else 1.0
	var has_fixed: bool = a.get("castTime") != null
	if not has_fixed and absf(ratio - 1.0) > 0.001:
		var base_as: float = float(a.attackSpeed)
		var bw := pct / base_as
		w = bw + (w - bw) * ratio
	w = minf(w, per)
	_check(c.alias + "_attack_windup", _near(win_meas, w, 0.035), "measured=%.3f expected=%.3f (AS %.3f pct %.4f ratio %.2f)" % [win_meas, w, as_total, pct, ratio])
	var exp_spd = null
	for n in a.attacks:
		if n.ends_with("BasicAttack") or n == c.alias + "BasicAttack":
			exp_spd = a.attacks[n].get("speed")
	if exp_spd == null:
		for n in a.attacks:
			exp_spd = a.attacks[n].get("speed")
			break
	if exp_spd != null and float(exp_spd) > 100.0 and not melee:
		_check(c.alias + "_attack_missile_speed", _near_rel(v0, float(exp_spd)), "ours=%.0f bin=%.0f measured=%.0f" % [v0, float(exp_spd), vmeas])
	_check(c.alias + "_attack_melee_flag", melee == bin_melee, "ours melee=%s bin range=%.0f" % [str(melee), float(T.attack.attackRange)])


func _run() -> void:
	await _wait(1.0)
	_setup()
	await _wait(0.5)
	print("TIME %s level=%d bonus_as=%.3f as=%.3f" % [c.alias, c.level, c.stats.bonus_as, c.stats.attack_speed])
	await _probe_attack()
	var dist := 5.0 if c.attack_range_m() > 3.0 else 2.0
	for s in 4:
		var key: String = "QWER"[s]
		var r: Dictionary = await _probe_slot(s, float(EXPECT.get(c.alias, {}).get(key, {}).get("dist", dist)))
		print("TIME %s %s %s" % [c.alias, key, _fmt(r)])
		var exp = _expected_cast(key, float(r.bonus_as))
		if exp != null and r.cast_total >= 0.0:
			var got: float = r.cast_total
			_check("%s_%s_cast_time" % [c.alias, key], _near(got, float(exp)), "ours=%.3f league=%.3f" % [got, float(exp)])
		var ex: Dictionary = EXPECT.get(c.alias, {}).get(key, {})
		if ex.has("dash"):
			_check("%s_%s_dash_time" % [c.alias, key], _near(float(r.dash), float(ex.dash), 0.06), "ours=%.3f league=%.3f" % [float(r.dash), float(ex.dash)])
		if ex.has("ms_min") and not r.missiles.is_empty():
			var vmin := INF
			for x in r.missiles:
				if x.accel < 0.0:
					vmin = minf(vmin, x.vmin)
			_check("%s_%s_missile_min_speed" % [c.alias, key], vmin < INF and _near_rel(vmin, float(ex.ms_min)), "ours=%.0f league=%.0f" % [vmin, float(ex.ms_min)])
		if ex.has("ms") and not r.missiles.is_empty():
			var mm: Dictionary = r.missiles[0]
			# the speed is sampled after the first tick: allow the acceleration of that frame
			var v_tol: float = absf(float(mm.accel)) / 60.0 * 1.5
			_check("%s_%s_missile_speed" % [c.alias, key], absf(mm.v0 - float(ex.ms)) <= maxf(float(ex.ms) * SPEED_TOL, 5.0) + v_tol, "ours=%.0f league=%.0f" % [mm.v0, float(ex.ms)])
			if ex.has("acc"):
				_check("%s_%s_missile_accel" % [c.alias, key], _near_rel(float(mm.accel), float(ex.acc)), "ours=%.0f league=%.0f" % [float(mm.accel), float(ex.acc)])
			if ex.has("ms_max"):
				var vmax := 0.0
				for x in r.missiles:
					vmax = maxf(vmax, x.vmax)
				_check("%s_%s_missile_peak_speed" % [c.alias, key], _near_rel(vmax, float(ex.ms_max)), "ours=%.0f league=%.0f" % [vmax, float(ex.ms_max)])
		elif ex.has("ms"):
			_check("%s_%s_missile_speed" % [c.alias, key], false, "no missile spawned")
	print("TIMING DONE %s passes=%d fails=%d" % [c.alias, passes, fails])
	get_tree().quit()
