extends Node
## [cc-anim] Crowd-control presentation probe. Applies every CC to the player champion (--champ=X) and to a lane minion,
## while the unit is running, and logs per 0.1 s: cc flags, animation, moving flag, ground speed, facing, model lift and
## the attached CC particles. Screenshots (camera on the subject) at --ccshots times after each CC starts.
##   tools/preview.sh 240 -- --champ=Ahri --harness=res://src/debug/cc_test.gd --shotdir=cc_ahri [--ccwho=champ|minion]
##       [--ccsel=stun,root,...] [--ccshots=0.3,1.0] [--cctime=1.6]
var main = null
var match_ref = null
var m = null
var subj: Unit = null
var src: Champion = null
var shot_dir := "user://cc_test"
var who := "champ"
var sel: Array = []
var shot_times: Array = [0.3, 1.2]
var cc_time := 1.6
var _rig = null
var _t0 := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
		elif a.begins_with("--ccwho="):
			who = a.substr(8)
		elif a.begins_with("--ccsel="):
			sel = Array(a.substr(8).split(","))
		elif a.begins_with("--ccshots="):
			shot_times = []
			for t in a.substr(10).split(","):
				shot_times.append(float(t))
		elif a.begins_with("--cctime="):
			cc_time = float(a.substr(9))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _gwait(s: float) -> void:
	## game-time wait
	var t: float = m.time + s
	while m.time < t:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("CCT SHOT ", ProjectSettings.globalize_path(path))


func _fx_names(u: Node) -> String:
	var out := []
	_scan(u, out)
	return ",".join(out)


func _scan(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is LolVfx:
			out.append(String(c.name))
		_scan(c, out)


func _state(tag: String, t: float, prev_pos: Vector3, dt: float) -> void:
	var sp: float = G.flat_dist(subj.global_position, prev_pos) / maxf(dt, 0.001)
	print("CCT %s t=%.2f cc=%d anim=%s top=%s moving=%s spd=%.1f face=%.0f lift=%.2f fx=[%s] cmd=%d" % [tag, t, subj.cc, subj.cur_anim, subj._g_top,
			subj.moving, sp, rad_to_deg(atan2(subj.facing.x, subj.facing.z)), subj.model.position.y if subj.model != null else 0.0,
			_fx_names(subj), subj.cmd])


func _clear_spot(around: Vector3) -> Vector3:
	var nav = m.nav
	for r in range(0, 60, 2):
		for k in 16:
			var q := around + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r
			var ok: bool = nav.is_walkable(q)
			for j in 12:
				if not ok:
					break
				var e := q + Vector3(cos(j * TAU / 12.0), 0, sin(j * TAU / 12.0)) * 9.0
				var e2 := q + Vector3(cos(j * TAU / 12.0), 0, sin(j * TAU / 12.0)) * 4.5
				if nav.brush_id(e) > 0 or nav.brush_id(e2) > 0 or nav.brush_id(q) > 0 or not nav.is_walkable(e2):
					ok = false
			if ok:
				return q
	return around


func _run() -> void:
	await _wait(1.0)
	m = G.match
	_rig = m.camera_rig
	var p: Champion = G.player
	p.controller = null
	for ch in m.champions:
		if ch != p:
			ch.controller = null
			ch.invulnerable_count += 1
			if ch.team != p.team and src == null:
				src = ch
			else:
				ch.teleport(ch.spawn_point)
	p.invulnerable_count += 1
	p.mana = 9999
	if m.hud != null:
		m.hud.visible = false
	var mid: Vector3 = _clear_spot((p.spawn_point + src.spawn_point) * 0.5)
	var east := Vector3(1, 0, 0)
	if who == "minion":
		var mn := Minion.new()
		mn.setup(p.team, Minion.Type.MELEE, 0, [mid + east * 60.0], 325.0)
		m.add_unit(mn, mid)
		mn.invulnerable_count += 1
		mn.think(0.0)
		subj = mn
		p.teleport(mid - east * 30.0)
	else:
		subj = p
	src.teleport(mid + Vector3(0, 0, 7.0))
	src.stats.base["attack_range"] = 150.0   # keep the taunter from running off; it stands still
	_rig.target = subj
	_rig.locked = true
	_rig.min_dist = 3.0
	_rig.target_distance = 7.0
	_rig.distance = 7.0
	await _wait(1.0)
	for bn in ["C_BUFFBONE_GLB_OVERHEAD_LOC", "C_BUFFBONE_GLB_HEAD_LOC", "BUFFBONE_CSTM_HEALTHBAR", "C_BUFFBONE_GLB_CENTER_LOC"]:
		var so := subj.socket(bn)
		print("CCT BONE %s %s y=%.2f (unit height %.2f size %.2f)" % [subj.display_name, bn, so.global_position.y - subj.global_position.y, subj.height, subj.stats.size])
	var all := ["none", "stun", "root", "charm", "taunt", "fear", "knockup", "knockback", "suppress", "sleep", "slow", "silence", "disarm", "polymorph"]
	for id in all:
		if not sel.is_empty() and not (id in sel):
			continue
		subj.teleport(mid)
		src.teleport(mid + Vector3(0, 0, 7.0))
		subj.cleanse()
		for b in subj.buffs.duplicate():
			subj.remove_buff(b)
		subj.cmd = Unit.Cmd.IDLE
		subj.issue_stop()
		await _gwait(0.5)
		subj.face_toward(mid + east * 10.0, 100.0)
		subj.issue_move(mid + east * 40.0)
		await _gwait(0.7)
		var buff: Buff = null
		match id:
			"stun": buff = K.stun(subj, cc_time, src)
			"root": buff = K.root(subj, cc_time, src)
			"charm": buff = K.charm(subj, cc_time, src, 0.65, {"lol": "Ahri_Base_E_buf", "bone": "C_BUFFBONE_GLB_HEAD_LOC"} if LolVfx.has("Ahri_Base_E_buf") else null)
			"taunt": buff = K.taunt(subj, cc_time, src)
			"fear": buff = K.fear(subj, cc_time, src)
			"knockup": buff = K.knockup(subj, cc_time * 0.6, src)
			"knockback": subj.knockback(subj.global_position - east * 4.0, 4.0, 0.6, src)
			"suppress": buff = K.suppress(subj, cc_time, src)
			"sleep": buff = K.sleep(subj, cc_time, src)
			"slow": buff = K.slow(subj, 0.5, cc_time, src)
			"silence": buff = K.silence(subj, cc_time, src)
			"disarm": buff = K.disarm(subj, cc_time, src)
			"polymorph":
				var b := Buff.new("polymorph", cc_time)
				b.cc = Buff.CC.POLYMORPH | Buff.CC.DISARM | Buff.CC.SILENCE
				b.is_debuff = true
				b.stats = {"ms": -60.0, "size": -0.6}
				subj.add_buff(b, src)
			_: pass
		print("CCT === %s on %s (%s) buff=%s" % [id, subj.display_name, who, buff != null])
		var t := 0.0
		var prev: Vector3 = subj.global_position
		var shots := shot_times.duplicate()
		var total := cc_time + 0.5
		while t < total:
			var tw: float = m.time
			await _gwait(0.1)
			var dt: float = m.time - tw
			t += dt
			_state(id, t, prev, dt)
			prev = subj.global_position
			if t > 0.45 and t < 0.6:
				_dump_fx(subj)
			if not shots.is_empty() and t >= shots[0]:
				shots.pop_front()
				await _shot("%s_%s_%03d" % [who, id, int(t * 100)])
	print("CCT DONE")
	get_tree().quit()


func _dump_fx(n: Node) -> void:
	for c in n.get_children():
		if c is LolVfx:
			var an = c._anchor
			var so = c._socket
			print("CCT FXPOS %s node_y=%.2f anchor_y=%s socket_y=%s unit_y=%.2f opts=%s" % [c.name, c.global_position.y - subj.global_position.y,
					"%.2f" % (an.global_position.y - subj.global_position.y) if an != null else "none",
					"%.2f" % (so.global_position.y - subj.global_position.y) if so != null else "none", subj.global_position.y, c._opts])
			for g in c.get_children():
				if g is Node3D:
					print("CCT    child %s y=%.2f" % [g.name, g.global_position.y - subj.global_position.y])
		_dump_fx(c)
