class_name AnimEvents
extends RefCounted
## [anim-events] League animation-graph events, driven generically from data (tools/lol/extract_anim.py ->
## data/anim/<unit>.json): every clip's mEventDataMap plays as the clip plays, for every unit with a graph or an
## events file (champions, minions, summons, turrets, structures).
##
##   Particle            the event's VFX system at each bone of mParticleEventDataPairList (Unit.socket), at its start
##                       frame; follows the bone, or is left in the world (mIsDetachable). Stopped at its end frame,
##                       and on clip exit when mIsKillEvent; persistent systems never outlive the clip by long.
##                       mIsLoop events fire again on every pass of a looping clip (a still-running persistent
##                       instance is kept instead of stacking a second one).
##   Sound               GameAudio (match.audio) at the unit; mIsLoop sounds re-fire on every loop pass.
##   SubmeshVisibility   shows / hides model submeshes (MeshInstance3D named after the League material range); the
##                       change is undone at its end frame or when the clip ends.
##   Fade                fades the model toward mTargetAlpha over mTimeToFade (undone on clip exit).
##   IdleParticlesVisibility  hides / shows the skin's idle particles (undone on clip exit).
## Skin idle particles (SkinCharacterDataProperties.idleParticlesEffects) are attached for the unit's life (removed
## while dead, restored on respawn); initialSubmeshToHide submeshes are hidden at bind.
##
## Clip time is the driver's clip clock: dt x the playing speed (attack-speed scaled attacks, run-rate matched runs),
## so frames land where League puts them. One instance per unit; no per-node _process, no per-event allocations
## beyond the spawned effect itself (option dictionaries are prebuilt per event).

const FPS := 30.0
const ORPHAN_LIFE := 1.5      ## s a persistent, non-kill particle survives the clip that started it
const ORPHAN_MAX := 4.0       ## s cap for any persistent instance left running (safety)

enum K { PARTICLE, SOUND, SUBMESH, FADE, IDLE_VIS, SNAP }
const _JointSnap := preload("res://src/core/joint_snap.gd")

static var _tables := {}      ## file (lower) -> table dictionary
static var stats := {"fired": 0, "particles": 0, "sounds": 0}   ## counters (harnesses / --animevlog)
static var _log: bool = "--animevlog" in OS.get_cmdline_user_args()
static var disabled: bool = "--noanimev" in OS.get_cmdline_user_args()   ## A/B: run without clip events
static var _abl_idle: bool = "--animev_noidle" in OS.get_cmdline_user_args()   ## ablation (perf A/B)
static var _abl_snap: bool = "--animev_nosnap" in OS.get_cmdline_user_args()
static var _abl_fx: bool = "--animev_nofx" in OS.get_cmdline_user_args()
static var debug_hook := Callable()   ## harnesses: called (unit, system, bone) after each event particle spawn

var unit = null               ## Unit
var tab: Dictionary = {}
var _evs: Array = []          ## events of the clip playing, sorted by time
var _clip := ""               ## atomic clip key ("" = none)
var _anim := ""               ## AnimationPlayer clip name of that clip
var _t := 0.0                 ## clip-local time (s)
var _len := 0.0
var _looping := false
var _next := 0
var _pass := 0                ## loop pass of the current clip
var _serial := 0
var _live: Array = []         ## [ev, LolVfx, serial]
var _orphans: Array = []      ## [LolVfx, match time deadline]
var _reverts: Array = []      ## [serial, end time or -1, Array meshes, Array previous visibility]
var _idle_fx: Array = []      ## LolVfx of the skin's idle particles
var _idle_on := false
var _idle_enabled := true
var _idle_hidden_serial := -1
var _fade_serial := -1
var _meshes_by_name := {}     ## submesh name (lower) -> Array[MeshInstance3D]
var _snap: Node = null        ## JointSnap modifier on the unit's skeleton (lazy)
var _snaps: Array = []        ## [serial, end time or -1, event] active joint snaps
## Kit-driven particle swaps {League system: replacement} — League swaps clips under buffs (Master Yi's Wuju Style
## attacks use the *_Wuju_Trail clip variants); kits set this instead of spawning their own copies.
var fx_swap := {}
var clip_events := true       ## false: skin idle particles only (the unit's own code runs its clip states)
var poll := false             ## also detect clips started on the AnimationPlayer directly (units without the graph driver)


# ===================================================================== data
## Event table of a data/anim file: {"clips": {atomic (lower): [ev]}, "by_anim": {anim (lower): atomic}, "idle": [...],
## "hidden": [...], "sounds": {event: true}}. Effects are resolved against the loaded VFX sets here, once.
static func table(file: String, g: AnimGraph = null) -> Dictionary:
	var key := file.to_lower()
	if _tables.has(key):
		return _tables[key]
	if g == null:
		g = AnimGraph.load_for(key)
	var t := {"clips": {}, "by_anim": {}, "idle": [], "hidden": [], "sounds": {}, "fx": {}, "count": 0}
	_tables[key] = t
	if g == null:
		return t
	var sets := {}
	for cn in g.clips:
		var node: Dictionary = g.clips[cn]
		var raw: Array = node.get("events", [])
		if raw.is_empty():
			continue
		var fps := float(node.get("fps", FPS))
		if fps <= 0.0:
			fps = FPS
		var list: Array = []
		for e in raw:
			var ev := _prep(e, fps, sets, t)
			if not ev.is_empty():
				list.append(ev)
		if list.is_empty():
			continue
		list.sort_custom(func(a, b): return float(a.t) < float(b.t))
		t.clips[cn] = list
		t.count += list.size()
		var an = node.get("anim")
		if an == null:
			an = node.get("xanim")
		if an != null:
			var al := String(an).to_lower()
			# legacy playback (no graph driver) finds the events by the exported clip name: the atomic clip whose
			# League name matches the exported one wins over variants sharing the same file
			if not t.by_anim.has(al) or cn == al:
				t.by_anim[al] = cn
	# Parallel clips play their first child (AnimGraph._resolve) while League layers the others on top with their
	# own events (Master Yi's attack trails live on the second layer): run those on the first child's clock
	for cn in g.clips:
		var pn: Dictionary = g.clips[cn]
		if String(pn.get("type", "")) != "Parallel":
			continue
		var l: Array = pn.get("list", [])
		if l.size() < 2:
			continue
		var first := String(l[0]).to_lower()
		if String(g.clips.get(first, {}).get("type", "")) != "Atomic":
			continue
		var merged: Array = t.clips.get(first, []).duplicate()
		var added := false
		for i in range(1, l.size()):
			for ev in t.clips.get(String(l[i]).to_lower(), []):
				var dup := false
				for ex in merged:
					if ex.get("k") == ev.get("k") and is_equal_approx(float(ex.t), float(ev.t)) \
							and ex.get("fx", ex.get("snd", "")) == ev.get("fx", ev.get("snd", "")):
						dup = true
						break
				if not dup:
					merged.append(ev)
					added = true
		if added:
			merged.sort_custom(func(a, b): return float(a.t) < float(b.t))
			t.count += merged.size() - t.clips.get(first, []).size()
			t.clips[first] = merged
	for ip in g.idle_particles:
		var nm := String(ip.get("effect", ""))
		if nm == "":
			continue
		sets[String(ip.get("set", ""))] = true
		var o := {"loop": true}
		var b := String(ip.get("bone", ""))
		if b != "":
			o["bone"] = b
		t.idle.append({"fx": nm, "opts": o})
	t.hidden = g.initial_hidden.duplicate()
	for s in sets:
		if s != "":
			LolVfx.load_set(s)
	return t


static func _prep(e: Dictionary, fps: float, sets: Dictionary, t: Dictionary) -> Dictionary:
	var ty := String(e.get("type", ""))
	var ev := {"t": maxf(float(e.get("start", 0.0)), 0.0) / fps, "te": -1.0,
			"loop": bool(e.get("loop", true)), "kill": bool(e.get("kill", true))}
	if e.has("end"):
		ev.te = float(e.end) / fps
	match ty:
		"Particle":
			var nm := String(e.get("effect", ""))
			if nm == "" or not e.has("set"):
				return {}   # no exported system (empty / sound-only League systems)
			sets[String(e.set)] = true
			ev.k = K.PARTICLE
			ev.fx = nm
			t.fx[nm] = true
			ev.detach = bool(e.get("detach", false))
			var bones: Array = []
			for b in e.get("bones", []):
				if not String(b).begins_with("#"):
					bones.append(String(b))
			if bones.is_empty():
				bones = [""]
			ev.bones = bones
			ev.opts = []   # per bone: prebuilt LolVfx options (filled with the loop flag at first fire)
		"Sound":
			var snd := String(e.get("sound", ""))
			if snd == "":
				return {}
			ev.k = K.SOUND
			ev.snd = snd
			t.sounds[snd] = true
		"SubmeshVisibility":
			ev.k = K.SUBMESH
			ev.show = e.get("show", [])
			ev.hide = e.get("hide", [])
		"Fade":
			ev.k = K.FADE
			ev.alpha = float(e.get("alpha", 1.0))
			ev.time = float(e.get("time", 0.0))
		"IdleParticlesVisibility":
			ev.k = K.IDLE_VIS
			ev.show = bool(e.get("show", false))
		"JointSnap":
			if String(e.get("joint", "")) == "" or String(e.get("snap_to", "")) == "":
				return {}
			ev.k = K.SNAP
			ev.joint = String(e.joint)
			ev.snap_to = String(e.snap_to)
		_:
			return {}   # FaceTarget / ConformToPath / LockRootOrientation: root-motion data, not run here
	return ev


# ===================================================================== binding
func _init(p_unit, p_tab: Dictionary) -> void:
	unit = p_unit
	tab = p_tab
	_apply_hidden()


## League initialSubmeshToHide (e.g. Yasuo's flute, shown only by his dance clip's SubmeshVisibility event).
func _apply_hidden() -> void:
	for h in tab.get("hidden", []):
		for mi in _meshes(String(h)):
			mi.visible = false


func has_sound(ev: String) -> bool:
	return tab.get("sounds", {}).has(ev)


## True when a clip event of this unit plays the VFX system (generic cast flashes skip their copy).
func binds_fx(nm: String) -> bool:
	return tab.get("fx", {}).has(nm)


func _meshes(nm: String) -> Array:
	if _meshes_by_name.is_empty() and unit.model != null:
		var stack: Array = [unit.model]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D:
				var k := String(n.name).replace("HIDDEN__", "").to_lower()
				if not _meshes_by_name.has(k):
					_meshes_by_name[k] = []
				_meshes_by_name[k].append(n)
		if _meshes_by_name.is_empty():
			_meshes_by_name["-"] = []
	return _meshes_by_name.get(nm.to_lower(), [])


## Model replaced: forget the old mesh index and bone-anchored instances.
func reset() -> void:
	_exit(true)
	_clear_idle()
	_meshes_by_name.clear()
	_clip = ""
	_anim = ""
	_apply_hidden()


# ===================================================================== clip playback
## The driver started a clip step. `restart_loop`: a cyclic state replaying the same clip (idle / run cycles), which
## counts as the next loop pass rather than a new play.
func on_clip(atomic: String, anim: String, length: float, looping: bool, restart_loop: bool = false) -> void:
	if not clip_events:
		_anim = anim
		return
	var key := atomic.to_lower()
	if key == "":
		key = tab.by_anim.get(anim.to_lower(), "")
	if restart_loop and key == _clip and key != "":
		_wrap()
		_len = length
		return
	_exit(false)
	_serial += 1
	_clip = key
	_anim = anim
	_evs = tab.clips.get(key, []) if key != "" else []
	_t = 0.0
	_len = maxf(length, 0.001)
	_looping = looping
	_next = 0
	_pass = 0


func _wrap() -> void:
	_t = 0.0
	_next = 0
	_pass += 1


## Advance the clip clock (dt x playing speed) and fire due events. Called every unit tick (also while dead).
func tick(dt: float, speed: float, ap: AnimationPlayer) -> void:
	if poll and ap != null:
		# clips started outside the driver (legacy units / code calling the AnimationPlayer directly)
		var cur := String(ap.current_animation)
		if cur != _anim and cur != "":
			var a := ap.get_animation(cur)
			on_clip("", cur, a.length if a != null else 1.0, a != null and a.loop_mode != Animation.LOOP_NONE)
	if not tab.idle.is_empty():
		_tick_idle()
	var tracked := not (_live.is_empty() and _reverts.is_empty() and _snaps.is_empty())
	if _evs.is_empty() and not tracked and _orphans.is_empty():
		return
	_t += dt * maxf(speed, 0.0)
	if _looping and _t >= _len and _len > 0.0:
		# fire what's left of this pass, then start the next one
		_fire_until(_len)
		_t = fmod(_t, _len)
		_next = 0
		_pass += 1
	if _next < _evs.size():
		_fire_until(_t)
	if tracked:
		_check_ends()
	if not _orphans.is_empty():
		_tick_orphans()


func _fire_until(t: float) -> void:
	while _next < _evs.size() and float(_evs[_next].t) <= t:
		var ev: Dictionary = _evs[_next]
		_next += 1
		if _pass > 0 and not ev.loop:
			continue   # mIsLoop false: first pass only
		_fire(ev)


func _check_ends() -> void:
	var i := 0
	while i < _live.size():
		var l: Array = _live[i]
		var fx = l[1]
		if not is_instance_valid(fx):
			_live.remove_at(i)
			continue
		var ev: Dictionary = l[0]
		if int(l[2]) == _serial and float(ev.te) >= 0.0 and _t >= float(ev.te) and (not _looping or _pass == int(l[3])):
			fx.stop()
			_live.remove_at(i)
			continue
		i += 1
	i = 0
	while i < _snaps.size():
		var sn: Array = _snaps[i]
		if int(sn[0]) == _serial and float(sn[1]) >= 0.0 and _t >= float(sn[1]):
			if is_instance_valid(_snap):
				_snap.remove_key(sn[2])
			_snaps.remove_at(i)
			continue
		i += 1
	i = 0
	while i < _reverts.size():
		var r: Array = _reverts[i]
		if int(r[0]) == _serial and float(r[1]) >= 0.0 and _t >= float(r[1]):
			_undo_submesh(r)
			_reverts.remove_at(i)
			continue
		i += 1


## The clip ended or was interrupted: kill events stop, persistent leftovers get a short grace, visibility reverts.
func _exit(all: bool) -> void:
	var now := _now()
	for l in _live:
		var fx = l[1]
		if not is_instance_valid(fx):
			continue
		var ev: Dictionary = l[0]
		if all or ev.kill:
			fx.stop()
		elif LolVfx.is_looping(String(ev.fx)):
			_orphans.append([fx, now + ORPHAN_LIFE])
	_live.clear()
	for r in _reverts:
		_undo_submesh(r)
	_reverts.clear()
	if not _snaps.is_empty():
		if is_instance_valid(_snap):
			_snap.clear()
		_snaps.clear()
	if _idle_hidden_serial >= 0:
		_idle_hidden_serial = -1
		_set_idle_visible(true)
	if _fade_serial >= 0 and unit != null:
		_fade_serial = -1
		unit.anim_fade = 0.0
	if all:
		for o in _orphans:
			if is_instance_valid(o[0]):
				o[0].stop()
		_orphans.clear()


func _tick_orphans() -> void:
	var now := _now()
	var i := 0
	while i < _orphans.size():
		var o: Array = _orphans[i]
		if not is_instance_valid(o[0]):
			_orphans.remove_at(i)
		elif now >= float(o[1]):
			o[0].stop()
			_orphans.remove_at(i)
		else:
			i += 1


func _now() -> float:
	var m = unit.match_ref if unit != null else null
	return float(m.time) if m != null else Time.get_ticks_msec() / 1000.0


# ===================================================================== firing
func _fire(ev: Dictionary) -> void:
	stats.fired += 1
	match int(ev.k):
		K.PARTICLE:
			_fire_particle(ev)
		K.SOUND:
			_fire_sound(ev)
		K.SUBMESH:
			_fire_submesh(ev)
		K.SNAP:
			_fire_snap(ev)
		K.FADE:
			_fade_serial = _serial
			unit.anim_fade = clampf(1.0 - float(ev.alpha), 0.0, 1.0)
		K.IDLE_VIS:
			if ev.show:
				_idle_hidden_serial = -1
				_set_idle_visible(true)
			else:
				_idle_hidden_serial = _serial
				_set_idle_visible(false)


func _fire_particle(ev: Dictionary) -> void:
	if _abl_fx:
		return
	var nm: String = ev.fx
	if not fx_swap.is_empty():
		nm = String(fx_swap.get(nm, nm))
	if not LolVfx.has(nm):
		return
	var persistent := LolVfx.is_looping(nm)
	if not persistent and (not unit._on_screen or not unit.visible):
		return   # a one-shot flash nobody can see (off screen / in fog): skip the spawn
	# a looping clip's next pass keeps a persistent instance that is still running instead of stacking another
	if _pass > 0 and persistent:
		for l in _live:
			if is_same(l[0], ev) and is_instance_valid(l[1]):
				l[3] = _pass
				return
	var bones: Array = ev.bones
	var opts: Array = ev.opts
	if opts.size() != bones.size() or (opts.size() > 0 and bool(opts[0].loop) != persistent):
		opts.clear()
		for b in bones:
			var o := {"loop": persistent, "max_life": ORPHAN_MAX if persistent else LolVfx.MAX_ONESHOT}
			if b != "":
				o["bone"] = b
			opts.append(o)
	var m = unit.match_ref
	for i in bones.size():
		var fx: LolVfx = null
		if ev.detach:
			if m == null or unit._fow_hidden:
				continue
			# left in the world where the bone is: non-ground emitters at the bone, ground ones on the ground under it
			var b: String = bones[i]
			var feet: Vector3 = unit.global_position
			var h := 0.0
			if b != "":
				var s: Node3D = unit.socket(b)
				if s != null and s.is_inside_tree() and s.global_position.is_finite():
					var bp := s.global_position
					feet = Vector3(bp.x, feet.y, bp.z)
					h = maxf(bp.y - feet.y, 0.0)
			fx = LolVfx.spawn(m, nm, feet, {"dir": unit.facing, "center": h})
		else:
			fx = LolVfx.attach(unit, nm, opts[i])
		if fx == null:
			continue
		fx.set_meta("anim_ev", true)   # animation-owned (harnesses tell these from kit effects)
		stats.particles += 1
		if _log:
			print("ANIMEV t=%.2f %s %s %s @%s" % [_now(), unit.display_name, _clip, nm, bones[i]])
		if debug_hook.is_valid():
			debug_hook.call(unit, nm, bones[i])
		if persistent or ev.kill or float(ev.te) >= 0.0:
			_live.append([ev, fx, _serial, _pass])


func _fire_sound(ev: Dictionary) -> void:
	var m = unit.match_ref
	if m == null or unit._fow_hidden:
		return
	var au = m.get("audio")
	if au == null or not au.has(ev.snd):
		return
	stats.sounds += 1
	au.play(ev.snd, unit.global_position, -2.0 if unit == G.player else -5.0)


func _fire_snap(ev: Dictionary) -> void:
	if _abl_snap:
		return
	var sk: Skeleton3D = unit._skel
	if sk == null or not is_instance_valid(sk):
		return
	var over: int = unit._find_bone(String(ev.joint))
	var to: int = unit._find_bone(String(ev.snap_to))
	if over < 0 or to < 0 or over == to:
		return
	for sn in _snaps:
		if is_same(sn[2], ev):
			return   # still active from the previous loop pass
	if _snap == null or not is_instance_valid(_snap) or _snap.get_parent() != sk:
		_snap = _JointSnap.new()
		_snap.name = "JointSnap"
		_snap.skel = sk
		sk.add_child(_snap)
	_snap.add(over, to, ev)
	_snaps.append([_serial, float(ev.te), ev])


func _fire_submesh(ev: Dictionary) -> void:
	var meshes: Array = []
	var prev: Array = []
	for nm in ev.hide:
		for mi in _meshes(String(nm)):
			meshes.append(mi)
			prev.append(mi.visible)
			mi.visible = false
	for nm in ev.show:
		for mi in _meshes(String(nm)):
			meshes.append(mi)
			prev.append(mi.visible)
			mi.visible = true
	if not meshes.is_empty():
		_reverts.append([_serial, float(ev.te), meshes, prev])


func _undo_submesh(r: Array) -> void:
	var meshes: Array = r[2]
	var prev: Array = r[3]
	for i in range(meshes.size() - 1, -1, -1):
		if is_instance_valid(meshes[i]):
			meshes[i].visible = prev[i]


# ===================================================================== skin idle particles
func _tick_idle() -> void:
	if tab.idle.is_empty() or unit == null or _abl_idle:
		return
	var want: bool = _idle_enabled and not unit.dead and unit.model != null and unit.is_inside_tree()
	if want == _idle_on:
		return
	_idle_on = want
	if want:
		for ip in tab.idle:
			if LolVfx.has(String(ip.fx)):
				var fx := LolVfx.attach(unit, String(ip.fx), ip.opts)
				if fx != null:
					fx.set_meta("anim_ev", true)
					_idle_fx.append(fx)
		if _idle_hidden_serial >= 0:
			_set_idle_visible(false)
	else:
		_clear_idle()


## Switch the skin idle particles off for good (a summon expiring) or back on.
func set_idle_enabled(on: bool) -> void:
	_idle_enabled = on
	if not on:
		_clear_idle()


func _clear_idle() -> void:
	for fx in _idle_fx:
		if is_instance_valid(fx):
			fx.stop()
	_idle_fx.clear()
	_idle_on = false


func _set_idle_visible(v: bool) -> void:
	for fx in _idle_fx:
		if is_instance_valid(fx):
			fx.visible = v


## Counts for reports: {clips with events, events, idle particles}.
static func describe(file: String) -> Dictionary:
	var t := table(file)
	return {"clips": t.clips.size(), "events": t.count, "idle": t.idle.size()}
