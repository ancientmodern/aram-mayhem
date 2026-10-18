extends Node
## QA harness for the kits-a champions (Ahri, Annie, Darius, Ezreal, Garen, Jinx, Leona).
## Casts every ability onto parked enemy champions and checks: damage is dealt, buffs/debuffs are applied
## and later removed, and no League VFX (LolVfx) / procedural VfxNode stays attached to a unit afterwards.
## Usage: godot --headless --path . --fixed-fps 60 -- --champ=Ezreal --harness=res://src/debug/kit_test_a.gd
## Output lines: "KIT PASS|FAIL <name> <detail>", final "KIT DONE <champ> fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var dummies: Array = []
var fails := 0
var passes := 0
var tracker: DmgTracker = null
var spot := Vector3.ZERO
## buff ids that legitimately persist (permanent passives etc.)
const PERSIST := ["harness_disarm"]
## effects that legitimately stay while a state lasts (Annie's stun-ready glow at 4 Pyromania stacks)
const PERSIST_FX := ["Annie_Base_StunReady", "Leona_Base_Idle_Sword", "Leona_Base_Idle_Shield", "Ahri_Base_Orb", "Ahri_Base_R_Eyes", "Ahri_Base_R_Ready_tar", "Annie_Base_Idle_fire"]


class DmgTracker extends Effect:
	var by_ability := {}   ## ability key -> total
	var by_tag := {}
	var attack := 0.0

	func _init() -> void:
		id = "harness_tracker"
		hidden = true

	func on_damage_dealt(info) -> void:
		var amt: float = info.final + info.absorbed
		if info.is_attack:
			attack += amt
		if info.ability != null:
			var k: String = str(info.ability.key) if "key" in info.ability else "?"
			by_ability[k] = by_ability.get(k, 0.0) + amt
		if info.tag != "":
			by_tag[info.tag] = by_tag.get(info.tag, 0.0) + amt

	func reset() -> void:
		by_ability.clear()
		by_tag.clear()
		attack = 0.0


func _ready() -> void:
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## Wait while keeping every test unit from auto attacking.
func _qwait(s: float) -> void:
	var t := 0.0
	while t < s:
		_quiet()
		await _frame()
		t += 1.0 / 60.0


func _frame() -> void:
	await get_tree().process_frame


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("KIT %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


# ===================================================================== arena
func _setup() -> void:
	m = G.match
	c = G.player
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
	# two enemy dummies in front of the player
	for ch in m.champions:
		if ch.team != c.team and dummies.size() < 2:
			dummies.append(ch)
	c.gain_xp(1.0e6)
	for i in 30:
		if not c.level_ability(3):
			for s in [0, 1, 2]:
				if c.level_ability(s):
					break
	c.add_effect(DmgTracker.new())
	tracker = c.find_effect("harness_tracker")
	for d in dummies:
		var b := Buff.new("harness_disarm", 1.0)
		b.permanent = true
		b.hidden = true
		b.cc = Buff.CC.DISARM
		b.cleansable = false
		d.add_buff(b, d)
		_neutralize(d)
	_reset_positions(4.0)


## Player at `spot`, dummies `dist` m in front (second one slightly behind / beside).
func _reset_positions(dist: float) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	c.teleport(spot)
	c.issue_move(spot)
	c.face_toward(spot + fwd, 1000.0)
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


func _ready_ability(slot: int) -> Ability:
	var ab: Ability = c.abilities[slot]
	ab.cd = 0.0
	if ab.max_charges > 0:
		ab.charges = ab.max_charges
	c.mana = c.stats.max_mana
	return ab


## Cast an ability at a unit (or point) the way the player controller does, then wait for the windup.
func _cast(slot: int, target, timeout: float = 2.0) -> bool:
	var ab := _ready_ability(slot)
	var pos: Vector3 = target.global_position if target is Node3D else target
	var hov = target if target is Unit else null
	var t := ab.make_target(pos, hov)
	var ok := ab.try_cast(t)
	var w := 0.0
	while w < timeout and (not c.casting.is_empty() or not c.pending_cast.is_empty()):
		await _frame()
		w += 1.0 / 60.0
	return ok


func _cast_wait(slot: int, target, settle: float) -> bool:
	var ok := await _cast(slot, target)
	await _wait(settle)
	return ok


## Dummies are real enemy champions: strip their own kit effects (passives such as Miss Fortune's Strut,
## Garen's Perseverance regen glow, Malphite's Granite Shield) and the visuals those already attached, so the
## lingering-VFX checks only see what the tested champion applied.
func _neutralize(d) -> void:
	for e in d.effects.duplicate():
		if e.id != "mayhem_aura" and not e.id.begins_with("harness") and not e.id.begins_with("kitb"):
			d.remove_effect(e)
	var nodes := []
	_collect_fx(d, nodes)
	for n in nodes:
		n.queue_free()


func _collect_fx(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is LolVfx or ch is VfxNode:
			out.append(ch)
		else:
			_collect_fx(ch, out)


# ===================================================================== inspection
func _fx_nodes(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is LolVfx or ch is VfxNode:
			out.append(ch)
		_fx_nodes(ch, out)


## Attached effects on a unit: [name, stopped] for every LolVfx / VfxNode below it.
func _attached(u: Node) -> Array:
	var out := []
	_fx_nodes(u, out)
	return out.filter(func(n): return not (String(n.name) in PERSIST_FX))


func _fx_desc(arr: Array) -> String:
	var names := []
	for n in arr:
		var s := String(n.name)
		if n is VfxNode:
			var kinds := []
			for ch in n.get_children():
				kinds.append(ch.get_class())
			s += "<VfxNode life=%.1f age=%.1f parent=%s %s>" % [n.lifetime, n._age, n.get_parent().name, "/".join(kinds)]
		if n is LolVfx and n._stopped:
			s += "(stopping)"
		names.append(s)
	return ",".join(names)


func _units() -> Array:
	return [c] + dummies


func _buff_ids(u) -> Array:
	var out := []
	for b in u.buffs:
		if not (b.id in PERSIST) and not b.permanent:
			out.append(b.id)
	return out


func _all_buffs() -> Dictionary:
	var d := {}
	for u in _units():
		d[u.display_name] = _buff_ids(u)
	return d


func _fx_count(u) -> int:
	return _attached(u).size()


## Wait until every non-persistent buff is gone and no effect is attached to the test units.
func _settle(name: String, max_t: float = 12.0) -> void:
	var t := 0.0
	while t < max_t:
		_quiet()
		var busy := false
		for u in _units():
			if not _buff_ids(u).is_empty() or _fx_count(u) > 0:
				busy = true
		if not busy and c.channel.is_empty() and c.dash.is_empty():
			_check(name + "_cleanup", true, "%.1fs" % t)
			return
		await _qwait(0.25)
		t += 0.25
	var det := []
	for u in _units():
		var bi := _buff_ids(u)
		var fx := _attached(u)
		if not bi.is_empty() or not fx.is_empty():
			det.append("%s buffs=[%s] fx=[%s]" % [u.display_name, ",".join(bi), _fx_desc(fx)])
	_check(name + "_cleanup", false, "; ".join(det))


## No auto attacks while waiting (League auto-acquires idle targets).
func _quiet() -> void:
	for u in _units():
		if u.attack_target != null and not u.dead:
			u.issue_move(u.global_position)


func _dmg(key: String) -> float:
	return float(tracker.by_ability.get(key, 0.0))


func _expect_damage(name: String, key: String) -> void:
	_check(name + "_damage", _dmg(key) > 0.0, "dealt=%.0f tags=%s" % [_dmg(key), str(tracker.by_tag)])


## Generic: cast, wait, check damage (optional) and cleanup.
func _basic(slot: int, target, settle: float, expect_dmg: bool = true, name: String = "") -> void:
	var key: String = "QWER"[slot]
	if name == "":
		name = c.alias + "_" + key
	_reset_positions(4.0 if c.attack_range_m() > 3.0 else 2.2)
	tracker.reset()
	await _frame()
	var ok := await _cast_wait(slot, target, settle)
	_check(name + "_cast", ok and c.abilities[slot].cd > 0.0 or c.abilities[slot].recast_window > 0.0 or c.abilities[slot].toggled,
			"cd=%.2f" % c.abilities[slot].cd)
	if expect_dmg:
		_expect_damage(name, key)
	await _settle(name)


# ===================================================================== per champion
func _run() -> void:
	await _wait(1.0)
	_setup()
	await _wait(0.5)
	var base_fx := []
	for u in _units():
		base_fx.append_array(_attached(u))
	if not base_fx.is_empty():
		print("KIT note baseline fx: ", _fx_desc(base_fx))
	match c.alias:
		"Ezreal": await _ezreal()
		"Ahri": await _ahri()
		"Annie": await _annie()
		"Darius": await _darius()
		"Garen": await _garen()
		"Jinx": await _jinx()
		"Leona": await _leona()
		_:
			for s in 4:
				await _basic(s, dummies[0], 2.0)
	# death cleanup: put every debuff the kit can apply on a dummy, then kill it
	await _death_cleanup()
	print("KIT DONE %s passes=%d fails=%d" % [c.alias, passes, fails])
	get_tree().quit()


func _death_cleanup() -> void:
	_reset_positions(3.0)
	tracker.reset()
	var d: Champion = dummies[0]
	for s in 4:
		if c.abilities[s].target_side == Ability.Side.ENEMY or c.abilities[s].indicator != Ability.Ind.NONE:
			await _cast(s, d)
			await _wait(0.15)
	await _wait(0.6)
	var before := _attached(d).size()
	if not d.dead:
		d.die(c)
	await _wait(3.0)
	var left := _attached(d)
	_check(c.alias + "_death_fx_removed", left.is_empty(), "attached_before=%d left=[%s]" % [before, _fx_desc(left)])
	d.respawn()
	# Ahri's Spirit Rush recast charges stay for the recast window (15 s, +10 s on a takedown)
	await _settle(c.alias + "_after_death", 28.0)
	await _owner_death()
	await _summoners()


## Self buffs / empowered states active when the champion dies must not leave looping effects on the corpse.
func _owner_death() -> void:
	_reset_positions(3.0)
	for s in 3:
		var ab: Ability = c.abilities[s]
		if ab.target_type == Ability.Target.NONE:
			await _cast(s, c)
			await _qwait(0.1)
	await _qwait(0.3)
	var before := _attached(c).size()
	c.die(dummies[0])
	await _wait(3.0)
	var left := _attached(c).filter(func(n): return not (n is LolVfx and n._stopped))
	_check(c.alias + "_owner_death_fx", left.is_empty(), "before=%d left=[%s]" % [before, _fx_desc(left)])
	c.respawn()
	await _settle(c.alias + "_after_owner_death", 12.0)


# --------------------------------------------------------------- summoner spells (kit_util / summoners.gd)
func _summ(slot: int, name: String) -> Ability:
	Summoners.set_spell(c, slot, name)
	return c.summoners[slot]


func _summoners() -> void:
	var d: Champion = dummies[0]
	_reset_positions(3.0)
	tracker.reset()
	# Ignite twice (refresh) -> one burn effect, gone after 5 s
	var ig := _summ(0, "Ignite")
	ig.try_cast({"pos": d.global_position, "dir": G.flat_dir(c.global_position, d.global_position), "unit": d})
	await _qwait(1.2)
	ig.cd = 0.0
	ig.try_cast({"pos": d.global_position, "dir": G.flat_dir(c.global_position, d.global_position), "unit": d})
	await _qwait(0.3)
	var burns := _attached(d).filter(func(n): return String(n.name).begins_with("Global_SS_Ignite"))
	_check("Summ_Ignite_single_fx", burns.size() == 1, _fx_desc(burns))
	_check("Summ_Ignite_damage", float(tracker.by_tag.get("burn", 0.0)) > 0.0, str(tracker.by_tag))
	await _settle("Summ_Ignite")
	# Barrier: bubble removed when the shield breaks
	var ba := _summ(1, "Barrier")
	ba.try_cast({"pos": c.global_position, "dir": c.facing, "unit": null})
	await _qwait(0.2)
	var bub_before := _attached(c).size()
	# margin: per-champion ARAM damage dealt/taken modifiers (MayhemAura, down to 0.9 x 0.95) must not leave a
	# sliver of shield
	Combat.deal(d, c, (c.total_shield() + 20.0) * 1.3, G.DmgType.TRUE, {})
	await _qwait(0.3)
	c.hp = c.stats.max_hp
	_check("Summ_Barrier_bubble_gone_on_break", bub_before > 0 and _attached(c).is_empty(), "before=%d after=[%s]" % [bub_before, _fx_desc(_attached(c))])
	await _settle("Summ_Barrier")
	# Mark: hit, target dies -> no free second snowball, tag removed
	_reset_positions(4.0)
	var mk := _summ(0, "Mark")
	mk.try_cast({"pos": d.global_position, "dir": G.flat_dir(c.global_position, d.global_position), "unit": null})
	for i in 60:
		await _qwait(1.0 / 60.0)
		if mk.recast_window > 0.0:
			break
	_check("Summ_Mark_hit", mk.recast_window > 0.0)
	d.die(c)
	await _qwait(0.2)
	_check("Summ_Mark_spent_on_death", mk.recast_window <= 0.0 and mk.cd > 1.0, "rw=%.1f cd=%.1f" % [mk.recast_window, mk.cd])
	await _qwait(3.0)
	d.respawn()
	await _settle("Summ_Mark")
	# Ghost buff + effect end together
	var gh := _summ(1, "Ghost")
	gh.try_cast({"pos": c.global_position, "dir": c.facing, "unit": null})
	await _qwait(0.2)
	_check("Summ_Ghost_buff", c.has_buff("ghost"))
	await _settle("Summ_Ghost", 13.0)


# --------------------------------------------------------------- Ezreal
func _ezreal() -> void:
	var d: Champion = dummies[0]
	await _basic(0, d, 1.5)
	# W mark -> applied, VFX attached; detonated by Q (not by W itself), mark + VFX removed
	_reset_positions(5.0)
	tracker.reset()
	await _cast(1, d)
	var mark: Buff = null
	for i in 90:
		await _frame()
		mark = d.find_buff("ezreal_w_mark", c)
		if mark != null:
			break
	_check("Ezreal_W_mark_applied", mark != null)
	_check("Ezreal_W_no_self_detonation", _dmg("W") == 0.0, "w_dmg=%.0f" % _dmg("W"))
	var fx_on := _attached(d)
	_check("Ezreal_W_mark_fx", not fx_on.is_empty(), _fx_desc(fx_on))
	var mana_before := c.mana
	await _cast(0, d)
	for i in 60:
		await _frame()
		if d.find_buff("ezreal_w_mark", c) == null:
			break
	await _wait(0.1)
	_check("Ezreal_W_detonated_by_Q", d.find_buff("ezreal_w_mark", c) == null and float(tracker.by_tag.get("w_det", 0.0)) > 0.0,
			"tags=%s" % str(tracker.by_tag))
	var after := _attached(d).filter(func(n): return String(n.name).begins_with("Ezreal_Base_W_tar"))
	_check("Ezreal_W_mark_fx_gone_on_detonate", after.is_empty(), _fx_desc(after))
	_check("Ezreal_W_mana_refund", c.mana > mana_before - c.abilities[0].cost() + 1.0, "mana %.0f -> %.0f" % [mana_before, c.mana])
	await _settle("Ezreal_W_Q")
	# W then basic attack detonates
	_reset_positions(4.0)
	tracker.reset()
	await _cast(1, d)
	await _wait(0.6)
	c.issue_attack(d)
	for i in 180:
		await _frame()
		if d.find_buff("ezreal_w_mark", c) == null:
			break
	c.issue_move(c.global_position)
	_check("Ezreal_W_detonated_by_attack", float(tracker.by_tag.get("w_det", 0.0)) > 0.0, "tags=%s" % str(tracker.by_tag))
	await _settle("Ezreal_W_attack")
	# W expiry after 4 s
	_reset_positions(5.0)
	tracker.reset()
	await _cast(1, d)
	await _qwait(0.8)
	var had := d.find_buff("ezreal_w_mark", c) != null
	var t_w := 0.0
	while t_w < 5.0 and d.find_buff("ezreal_w_mark", c) != null:
		await _qwait(0.1)
		t_w += 0.1
	_check("Ezreal_W_mark_expires", had and d.find_buff("ezreal_w_mark", c) == null, "had=%s gone_after=%.1fs w_det=%.0f" % [had, t_w + 0.8, float(tracker.by_tag.get("w_det", 0.0))])
	await _settle("Ezreal_W_expire")
	# E blink + bolt, R
	await _basic(2, d.global_position, 1.0)
	await _basic(3, d, 1.5)


# --------------------------------------------------------------- Ahri
func _ahri() -> void:
	var d: Champion = dummies[0]
	await _basic(0, d, 2.0)
	await _basic(1, d, 2.0)
	await _basic(2, d, 1.0)
	# R: three dashes
	_reset_positions(4.0)
	tracker.reset()
	for i in 3:
		var r: Ability = c.abilities[3]
		r.dash_lock = 0.0
		var t := r.make_target(d.global_position + Vector3(1.5 * (i - 1), 0, 0), null)
		r.try_cast(t)
		await _wait(1.1)
	_check("Ahri_R_three_casts", c.abilities[3].cd > 0.0 and c.abilities[3].recast_window <= 0.0, "cd=%.1f rw=%.1f" % [c.abilities[3].cd, c.abilities[3].recast_window])
	_expect_damage("Ahri_R", "R")
	await _settle("Ahri_R")


# --------------------------------------------------------------- Annie
func _annie() -> void:
	var d: Champion = dummies[0]
	await _basic(0, d, 1.0)
	await _basic(1, d, 1.0)
	await _basic(2, c, 0.5, false)
	# E reflect on a hit
	await _basic(3, d.global_position, 1.0)
	# Tibbers stays (summon) - remove it so the cleanup check is about buffs/VFX
	for u in m.units.duplicate():
		if u.kind == G.Kind.SUMMON:
			u.die(null)
	await _settle("Annie_tibbers_gone")


# --------------------------------------------------------------- Darius
func _darius() -> void:
	var d: Champion = dummies[0]
	_reset_positions(3.3)
	tracker.reset()
	await _cast(0, d)
	await _wait(1.3)
	_expect_damage("Darius_Q", "Q")
	_check("Darius_Q_hemo", d.find_buff("darius_hemo") != null)
	await _settle("Darius_Q")
	# W empowered attack
	_reset_positions(1.8)
	tracker.reset()
	await _cast(1, c)
	c.issue_attack(d)
	await _wait(1.5)
	c.issue_move(c.global_position)
	_check("Darius_W_hit", float(tracker.by_tag.get("darius_w", 0.0)) > 0.0, "tags=%s" % str(tracker.by_tag))
	await _settle("Darius_W")
	await _basic(2, d, 1.0, false)
	await _basic(3, d, 1.5)


# --------------------------------------------------------------- Garen
func _garen() -> void:
	var d: Champion = dummies[0]
	_reset_positions(1.8)
	tracker.reset()
	await _cast(0, c)
	c.issue_attack(d)
	await _wait(1.5)
	c.issue_move(c.global_position)
	_check("Garen_Q_hit", float(tracker.by_tag.get("garen_q", 0.0)) > 0.0, "tags=%s" % str(tracker.by_tag))
	await _settle("Garen_Q")
	await _basic(1, c, 0.5, false)
	_reset_positions(1.8)
	tracker.reset()
	await _cast(2, c)
	await _wait(3.4)
	_expect_damage("Garen_E", "E")
	await _settle("Garen_E")
	# E recast ends the spin early
	_reset_positions(1.8)
	await _cast(2, c)
	await _wait(0.8)
	c.abilities[2].try_cast(c.abilities[2].make_target(c.global_position, null))
	await _wait(0.1)
	_check("Garen_E_recast_ends", c.channel.is_empty() and c.abilities[2].cd > 0.0, "cd=%.1f" % c.abilities[2].cd)
	await _settle("Garen_E_recast")
	d.hp = d.stats.max_hp * 0.3
	await _basic(3, d, 1.0)


# --------------------------------------------------------------- Jinx
func _jinx() -> void:
	var d: Champion = dummies[0]
	_reset_positions(4.0)
	tracker.reset()
	await _cast(0, c)
	_check("Jinx_Q_rockets", c.abilities[0].rockets and c.casting.is_empty())
	c.issue_attack(d)
	await _wait(2.0)
	c.issue_move(c.global_position)
	_check("Jinx_Q_rocket_hit", float(tracker.by_tag.get("jinx_rocket", 0.0)) > 0.0, "tags=%s" % str(tracker.by_tag))
	await _cast(0, c)
	await _settle("Jinx_Q")
	await _basic(1, d, 1.0)
	await _basic(2, d.global_position, 2.5)
	await _basic(3, d, 1.5)


# --------------------------------------------------------------- Leona
func _leona() -> void:
	var d: Champion = dummies[0]
	_reset_positions(1.6)
	tracker.reset()
	await _cast(0, c)
	c.issue_attack(d)
	await _wait(1.5)
	c.issue_move(c.global_position)
	_expect_damage("Leona_Q", "Q")
	await _settle("Leona_Q")
	_reset_positions(2.5)
	tracker.reset()
	await _cast(1, c)
	await _wait(3.5)
	_expect_damage("Leona_W", "W")
	await _settle("Leona_W")
	await _basic(2, d, 1.2)
	await _basic(3, d.global_position, 1.5)
