class_name HexgateNet
extends Node
## [env3] Howling Abyss hexgates ("Frost-gates"): one-way, ally/enemy-usable fast travel from a team's base to the lane.
##
## What is League data and what is inferred:
##  * placements, models (HA_Hexgate / HA_Hexgate_Exit), animation clips (idle1 / spawn / click / open / open_loop /
##    close), particle systems and the sound events come from Map12 (HA_Hexgate*.bin animation graphs + the
##    dde709c7 / 30b093d2 resource resolvers, extracted by tools/lol/extract_hexgate.py into data/vfx/hexgate.json).
##  * rules follow the League wiki (Warp gate / Howling Abyss): the gate sends champions from the base toward the
##    lane only; the exit is the allied outer turret until it falls, then the allied inhibitor turret for the rest of
##    the game (the other exit gate disappears / reappears); either team can use a gate; 0.75 s channel that any
##    damage / non-hold order / hard CC interrupts (1.5 s lockout); 2.25 s untargetable dash to the exit; a 250 unit
##    follow-up dash past the exit; 15 s per-champion cooldown shared by every gate.
##
## The net drives itself (no match.gd tick hook): the human uses a gate by right-clicking it (a move order whose goal
## is on the gate), bots use their own team's gate when they are in the base and heading for the lane.

const CHANNEL_TIME := 0.75
const TRAVEL_TIME := 2.25
const REPOSITION_DIST := 2.5       ## 250 League units
const REPOSITION_TIME := 0.28
const COOLDOWN := 15.0
const LOCKOUT := 1.5
const CLICK_RADIUS := 2.4          ## move goal within this of an entry gate counts as clicking it
const ENTER_RADIUS := 1.9          ## champion within this of the gate centre starts the channel
const BOT_RANGE := 30.0            ## bots consider the gate inside this distance of it
const SND := "Play_sfx_Env_Map12_SRX_Hextech_"

var m = null
var gates: Array = []              ## {kind, team, pos, fwd, yaw, node, active, idx, fx[], ap}
var entries := [null, null]
var exits := [[null, null], [null, null]]     ## per team: [outer exit, inhibitor exit]
var _cd := {}                      ## champion -> time its cooldown ends (shared by every gate)
var _lockout := {}                 ## champion -> time it may try again
var _pending := {}                 ## champion -> {gate, goal}   (walking to a gate)
var _bot_t := 0.0
var _bot_plan := {}               ## bot -> time it will walk into the gate (INF = walks)
var _poll_t := 0.0
var _started := false
var _exit_state := [0, 0]          ## per team: index of the exit currently in use
var _opens := {}                   ## team -> {until, ...} bookkeeping for the open portal visuals
var _log_on := "--hexlog" in OS.get_cmdline_user_args()


func setup(p_match, props: Array) -> void:
	m = p_match
	LolVfx.load_set("hexgate")
	for p in props:
		var nm: String = p.name
		var exit: bool = nm.ends_with("Exit")
		var team: int = G.Team.ORDER if p.pos.x - p.pos.z < 130.0 else G.Team.CHAOS
		var g := {"kind": "exit" if exit else "entry", "team": team, "pos": p.pos, "yaw": p.yaw,
				"fwd": Basis(Vector3.UP, p.yaw) * Vector3.FORWARD, "node": null, "active": false, "idx": 0,
				"fx": [], "ap": null, "open_fx": [], "pos_n": p.pos, "exit": exit}
		var mdl := Assets.unit_model(nm, 0)
		if mdl != null:
			m.world_root.add_child(mdl)
			var gp: Vector3 = p.pos
			if m.nav != null:
				gp.y = m.nav.height_at(gp)
			g.pos = gp
			mdl.global_position = gp
			mdl.rotation.y = p.yaw
			g.node = mdl
			var ap = Assets._find_anim(mdl)
			g.ap = ap
			if ap != null:
				for an in ["idle1", "open_loop"]:
					if ap.has_animation(an):
						ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
				if ap.has_animation("idle1"):
					ap.play("idle1")
		else:
			g.pos = p.pos
		gates.append(g)
		m.hexgates.append(g)
	# link exits to the team's turrets: the exit nearest the outer turret is the first one
	for team in 2:
		var ents := gates.filter(func(x): return x.kind == "entry" and x.team == team)
		entries[team] = ents[0] if not ents.is_empty() else null
		var exs := gates.filter(func(x): return x.kind == "exit" and x.team == team)
		var outer = m.outer_turrets[team]
		exs.sort_custom(func(a, b):
			var ref: Vector3 = outer.global_position if outer != null else Vector3.ZERO
			return G.flat_dist(a.pos, ref) < G.flat_dist(b.pos, ref))
		for i in mini(exs.size(), 2):
			exs[i].idx = i
			exits[team][i] = exs[i]
	for team in 2:
		var e = entries[team]
		if e != null:
			e.active = true
		if exits[team][0] != null:
			exits[team][0].active = true
		if exits[team][1] != null:
			exits[team][1].active = false
			if exits[team][1].node != null:
				exits[team][1].node.visible = false
	set_process(true)


func _log(msg: String) -> void:
	if _log_on:
		print("HEXGATE t=%.2f %s" % [m.time, msg])


func viewer_team() -> int:
	return G.player.team if G.player != null else G.Team.ORDER


## League plays the "_Enemy" variants of a gate's effects for the team that doesn't own it.
func _vname(base: String, team: int) -> String:
	var n := "HA_Hexgate_" + base
	if team != viewer_team() and LolVfx.has(n + "_Enemy"):
		return n + "_Enemy"
	return n


func _fx(name: String, g: Dictionary, opts: Dictionary = {}):
	if not LolVfx.has(name):
		return null
	var o := {"dir": g.fwd}
	o.merge(opts, true)
	return LolVfx.spawn(m, name, g.pos, o)


func _snd(ev: String, pos: Vector3, ally: bool = true) -> void:
	if m.audio != null:
		m.audio.play(ev, pos, 0.0)


func _anim(g: Dictionary, an: String) -> void:
	var ap = g.ap
	if ap == null or not ap.has_animation(an):
		return
	ap.play(an)
	if an != "idle1" and an != "open_loop" and ap.has_animation("idle1"):
		ap.queue("idle1")


## The exit gate currently in use for a team.
func active_exit(team: int):
	var e = exits[team][_exit_state[team]]
	if e == null:
		e = exits[team][0] if exits[team][0] != null else exits[team][1]
	return e


## Called by match.gd when a structure falls (outer turret -> the exit moves to the inhibitor turret).
func structure_fell() -> void:
	for team in 2:
		var outer = m.outer_turrets[team]
		if _exit_state[team] == 0 and outer != null and outer.dead and exits[team][1] != null:
			_swap_exit(team)


func _swap_exit(team: int) -> void:
	_exit_state[team] = 1
	var old = exits[team][0]
	var nw = exits[team][1]
	if old != null:
		old.active = false
		_fx("HA_Hexgate_Exit_Base_Disappear", old)
		_snd(SND + "Hexgate_buffdeactivate", old.pos)
		_anim(old, "close")
		m.after(0.9, func():
			if old.node != null and not old.active:
				old.node.visible = false)
	if nw != null:
		nw.active = true
		if nw.node != null:
			nw.node.visible = true
		_fx("HA_Hexgate_Exit_Base_Reappear", nw)
		_fx("HA_Hexgate_Exit_Base_PortalSpawn", nw)
		_snd(SND + "Spawn_cast", nw.pos)
		_anim(nw, "spawn")


func _intro() -> void:
	_started = true
	for g in gates:
		if not g.active:
			continue
		_anim(g, "spawn")
		_fx("HA_Hexgate_Exit_Base_PortalSpawn" if g.kind == "exit" else "HA_Hexgate_Base_PortalSpawn", g)
		_snd(SND + "Spawn_cast", g.pos)


# ===================================================================== per frame
func _process(dt: float) -> void:
	if m == null or m.paused:
		return
	if not _started and m.time > 0.4:
		_intro()
	_poll_t -= dt
	if _poll_t <= 0.0:
		_poll_t = 0.5
		structure_fell()
	# human: a move order whose goal is on an entry gate
	var pl = G.player
	if pl != null and is_instance_valid(pl) and not pl.dead and not pl.is_bot:
		_watch_player(pl)
	for c in _pending.keys():
		_walk_to_gate(c)
	_bot_t -= dt
	if _bot_t <= 0.0:
		_bot_t = 0.3
		_bots()


func cooldown_left(c) -> float:
	return maxf(0.0, float(_cd.get(c, 0.0)) - m.time)


func can_start(c) -> bool:
	if c == null or not is_instance_valid(c) or c.dead:
		return false
	if m.time < float(_lockout.get(c, 0.0)) or m.time < float(_cd.get(c, 0.0)):
		return false
	if (c.cc & (Buff.BLOCK_CAST | Buff.CC.GROUNDED)) != 0:
		return false
	return c.dash.is_empty() and c.channel.is_empty() and c.casting.is_empty()


func _gate_at_goal(goal: Vector3):
	for e in entries:
		if e != null and G.flat_dist(goal, e.pos) <= CLICK_RADIUS:
			return e
	return null


func _watch_player(pl) -> void:
	if _pending.has(pl):
		return
	if pl.cmd != Unit.Cmd.MOVE:
		return
	var g = _gate_at_goal(pl.move_goal)
	if g == null or active_exit(g.team) == null:
		return
	_clicked(pl, g)


func _clicked(c, g: Dictionary) -> void:
	_pending[c] = {"gate": g, "goal": c.move_goal, "t": m.time}
	var ally: bool = c.team == viewer_team()
	_snd(SND + "Hexgate_Click_Ally_cast" if ally else SND + "Hexgate_Click_Enemy_cast", g.pos)
	_anim(g, "click")


func _walk_to_gate(c) -> void:
	var st: Dictionary = _pending[c]
	var g: Dictionary = st.gate
	if not is_instance_valid(c) or c.dead:
		_drop(c)
		return
	# the order was replaced (right-click elsewhere, attack, stop, cast): drop it
	if c.is_bot:
		if m.time - st.t > 20.0:
			_drop(c)
			return
	elif c.cmd != Unit.Cmd.MOVE or G.flat_dist(c.move_goal, st.goal) > 0.2:
		if G.flat_dist(c.global_position, g.pos) > ENTER_RADIUS + 0.4:
			_drop(c)
			return
	var d := G.flat_dist(c.global_position, g.pos)
	var arrived: bool = d <= ENTER_RADIUS or (not c.moving and d <= ENTER_RADIUS + 1.6)
	if not arrived:
		if c.is_bot and (not c.moving or c.cmd != Unit.Cmd.MOVE):
			c.issue_move(g.pos)
		return
	_pending.erase(c)
	if c.has_meta("hexgate_busy"):
		c.remove_meta("hexgate_busy")
	if can_start(c):
		_begin_channel(c, g)


func _drop(c) -> void:
	_pending.erase(c)
	if is_instance_valid(c) and c.has_meta("hexgate_busy"):
		c.remove_meta("hexgate_busy")


## True while a bot is walking to / using a gate (BotBrain.think skips its decisions meanwhile).
func claims(c) -> bool:
	return c.has_meta("hexgate_busy")


func _bots() -> void:
	for c in m.champions:
		if c.dead or not c.is_bot or not (c.controller is BotBrain) or _pending.has(c) or not c.channel.is_empty() or not c.dash.is_empty():
			continue
		var g = entries[c.team]
		if g == null or not g.active or active_exit(c.team) == null:
			continue
		if not can_start(c) or G.flat_dist(c.global_position, g.pos) > BOT_RANGE:
			continue
		if m.time - c.last_damaged_time < 4.0 or c.hp_ratio() < 0.2:
			continue
		var bb = c.controller
		if bb == null or bb.mode != "lane":
			continue
		# only worth it when the exit is a real shortcut and nobody dangerous is near the gate
		var ex = active_exit(c.team)
		if G.flat_dist(c.global_position, ex.pos) < G.flat_dist(g.pos, ex.pos) * 0.6:
			continue
		var busy := false
		for e in m.champions:
			if e.team != c.team and not e.dead and G.flat_dist(e.global_position, c.global_position) < 14.0:
				busy = true
				break
		if busy:
			continue
		# each bot decides once per trip whether it takes the gate, and reacts after a human-ish delay
		if not _bot_plan.has(c):
			_bot_plan[c] = m.time + G.rng.randf_range(0.4, 4.5) if G.rng.randf() < 0.8 else INF
		if m.time < float(_bot_plan[c]):
			continue
		_bot_plan.erase(c)
		c.set_meta("hexgate_busy", true)
		c.issue_move(g.pos)
		_pending[c] = {"gate": g, "goal": g.pos, "t": m.time}


# ===================================================================== channel / travel
class HexChannel extends Ability:
	var net: HexgateNet = null
	var gate: Dictionary = {}
	var dest: Dictionary = {}
	var started := 0.0
	var fx: Array = []
	var finished := false

	func channel_tick(_dt: float, _ch: Dictionary) -> void:
		var o = owner
		# damage, any order that isn't hold/stop, spell casts and hard CC interrupt the channel
		if o.last_damaged_time >= started or (o.cmd != Unit.Cmd.IDLE and o.cmd != Unit.Cmd.HOLD) or not o.casting.is_empty() \
				or (o.cc & (Buff.BLOCK_CAST | Buff.CC.GROUNDED)) != 0:
			o.interrupt_channel(true)

	func channel_end(_ch: Dictionary, interrupted: bool) -> void:
		if finished:
			return
		finished = true
		net._channel_done(self, interrupted)


func _begin_channel(c, g: Dictionary) -> void:
	var ex = active_exit(g.team)
	if ex == null:
		return
	c.issue_stop()
	var ab := HexChannel.new(c)
	ab.net = self
	ab.gate = g
	ab.dest = ex
	ab.display_name = "Hexgate"
	ab.started = m.time
	ab.uninterruptible = false
	ab.can_move_while_channeling = false
	ab.start_channel(CHANNEL_TIME)
	c.set_meta("hexgate_busy", true)
	var ally: bool = c.team == viewer_team()
	# gate opens on both ends; channel cones on the champion; indicator chain gate -> exit; destination marker
	_open(g, ex, g.team)
	var chn := "HA_Hexgate_Channel_Ally" if ally else "HA_Hexgate_Channel_Enemy"
	var f = LolVfx.attach(c, chn, {})
	if f != null:
		ab.fx.append(f)
	var dist := G.flat_dist(g.pos, ex.pos)
	var dir := G.flat_dir(g.pos, ex.pos)
	var beam = LolVfx.spawn(m, "HA_Hexgate_Indicator_Beam", g.pos + Vector3(0, 0.1, 0), {"dir": dir, "length": dist, "loop": true})
	if beam != null:
		ab.fx.append(beam)
	var dm = LolVfx.spawn(m, "HA_Hexgate_Unit_Destination_Ally" if ally else "HA_Hexgate_Unit_Destination_Enemy", ex.pos, {"dir": ex.fwd})
	if dm != null:
		ab.fx.append(dm)
	_snd(SND + "Hexgate_cast", g.pos)
	_log("%s channel at %s team %d -> exit %d" % [c.display_name, "entry", g.team, ex.idx])


func _open(g: Dictionary, ex: Dictionary, team: int) -> void:
	for gate in [g, ex]:
		var pre := "Exit_Base_" if gate.kind == "exit" else "Base_"
		for k in gate.open_fx:
			if is_instance_valid(k):
				k.stop()
		gate.open_fx = []
		var f = _fx(_vname(pre + "PortalOpen", team), gate, {"loop": true})
		if f != null:
			gate.open_fx.append(f)
		var f2 = _fx(_vname(pre + "OpenLoop", team), gate)
		if f2 != null:
			gate.open_fx.append(f2)
		_anim(gate, "open")


func _close(gate: Dictionary, team: int) -> void:
	var pre := "Exit_Base_" if gate.kind == "exit" else "Base_"
	for k in gate.open_fx:
		if is_instance_valid(k):
			k.stop()
	gate.open_fx = []
	_fx(_vname(pre + "ClosePortal", team), gate)
	_anim(gate, "close")


func _channel_done(ab: HexChannel, interrupted: bool) -> void:
	var c = ab.owner
	for f in ab.fx:
		if is_instance_valid(f):
			f.stop()
	if interrupted or c == null or not is_instance_valid(c) or c.dead:
		if c != null and is_instance_valid(c):
			_lockout[c] = m.time + LOCKOUT
			if c.has_meta("hexgate_busy"):
				c.remove_meta("hexgate_busy")
		_close(ab.gate, ab.gate.team)
		_close(ab.dest, ab.gate.team)
		_log("%s channel interrupted" % [c.display_name if c != null and is_instance_valid(c) else "?"])
		return
	_depart(c, ab.gate, ab.dest)


func _depart(c, g: Dictionary, ex: Dictionary) -> void:
	var ally: bool = c.team == viewer_team()
	_cd[c] = m.time + COOLDOWN
	_snd(SND + "Hexgate_Enter_cast", g.pos)
	_fx("HA_Hexgate_Channel_Complete_Outgoing_Ally" if ally else "HA_Hexgate_Channel_Complete_Outgoing_Enemy", g)
	_fx(_vname("Base_PortalOutgoing", g.team), g)
	# untargetable for the whole trip (a buff, so it also clears if the champion dies)
	var b := Buff.new("hexgate_travel", TRAVEL_TIME + 0.4)
	b.cc = Buff.CC.UNTARGETABLE
	b.hidden = true
	c.add_buff(b, null)
	# the dash follows the walkable lane polyline (the straight line cuts through walls)
	var pts: PackedVector3Array = m.nav.find_path(g.pos, ex.pos) if m.nav != null else PackedVector3Array([g.pos, ex.pos])
	if pts.size() < 2:
		pts = PackedVector3Array([g.pos, ex.pos])
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + G.flat_dist(pts[i - 1], pts[i]))
	var total := maxf(cum[cum.size() - 1], 0.01)
	var mis = LolVfx.attach(c, "HA_Hexgate_Mis_Ally" if ally else "HA_Hexgate_Mis_Enemy", {"missile": false})
	var state := {"i": 1}
	c.global_position = Vector3(g.pos.x, c.global_position.y, g.pos.z)
	c.start_dash(ex.pos, {"duration": TRAVEL_TIME, "can_cast": false,
		"on_tick": func(u, k: float):
			var s := k * total
			var i: int = state.i
			while i < pts.size() - 1 and cum[i] < s:
				i += 1
			state.i = i
			var seg := maxf(cum[i] - cum[i - 1], 0.0001)
			var t := clampf((s - cum[i - 1]) / seg, 0.0, 1.0)
			var p := pts[i - 1].lerp(pts[i], t)
			u.set_ground_pos(p)
			u.face_toward(pts[i], 100.0),
		"on_arrive": func(u):
			if mis != null and is_instance_valid(mis):
				mis.stop()
			_arrive(u, g, ex)})


func _arrive(c, g: Dictionary, ex: Dictionary) -> void:
	var ally: bool = c.team == viewer_team()
	if not is_instance_valid(c):
		return
	c.set_ground_pos(ex.pos)
	_log("%s arrived at exit %d" % [c.display_name, ex.idx])
	_fx("HA_Hexgate_Channel_Complete_Incoming_Ally" if ally else "HA_Hexgate_Channel_Complete_Incoming_Enemy", ex)
	_fx(_vname("Exit_Base_PortalIncoming", g.team), ex)
	_snd(SND + "Hexgate_Land_hit", ex.pos)
	# follow-up dash 250 units past the exit (toward the lane)
	var to: Vector3 = ex.pos + ex.fwd * REPOSITION_DIST
	_snd(SND + "Hexgate_Directional_cast", ex.pos)
	c.start_dash(to, {"duration": REPOSITION_TIME, "can_cast": false,
		"on_arrive": func(u):
			if is_instance_valid(u) and u.has_meta("hexgate_busy"):
				u.remove_meta("hexgate_busy")})
	m.after(1.4, func():
		_close(g, g.team)
		_close(ex, g.team))
	# local cooldown rings on every active gate (League shows the timer ring while a gate is unusable for you):
	# the ring system runs 10 s, so it starts when 10 s of the 15 s cooldown remain
	if c == G.player:
		m.after(maxf(0.1, COOLDOWN - 10.0 - TRAVEL_TIME - REPOSITION_TIME - 1.4), func():
			for gg in gates:
				if gg.active:
					_fx("HA_Hexgate_Base_Timer_Ring_10s", gg))
