extends Node
## [vfx-leak] Lingering-effect detector. Tracks every live LolVfx instance (attached and world) through a long match
## and flags the ways an effect outlives the thing that spawned it. Usage (headless, long):
##   godot --headless --path . --fixed-fps 60 -- --sim --time=600 --seed=11 --harness=res://src/debug/vfx_leak_probe.gd
## Optional: --leak_age=N (seconds an unreferenced loop may live, default 10), --leak_every=N (report every N s).
##
## Flags (each instance is flagged once per kind):
##   LOOP_UNREF        looping effect, not stopped, older than leak_age and referenced by nothing that could stop it
##                     (no buff.vfx / extra_fx, no kit / ability / effect / anim-event field, not a missile visual)
##   BUFF_END_ALIVE    effect bound to a buff.vfx that has ended and the effect is still unstopped >0.6 s later
##   BUFF_END_LINGER   same, but already stop()ped and still alive >0.6 s after the buff ended (League kills it)
##   DEAD_HOST         unstopped looping effect on a dead unit for >1.5 s
##   NOT_IN_TREE       live LolVfx registered with the hub that is no longer in the scene tree for >1 s
##   AGE_ONESHOT       non-looping effect alive > max(3 x its capped natural duration, 2 s)
##   OVERDUE_FREE      stopped effect alive >1.5 s beyond its scheduled free time
##   ANIM_UNTRACKED    anim-event persistent effect that its unit's AnimEvents no longer tracks (not stopped)
##   ANIM_STALE        anim-event effect tracked under a clip serial that already ended (clip exit missed it)
##   ANIM_PAST_END     anim-event effect still unstopped >0.5 s after its event end frame
##   ANIM_PAST_CLIP    persistent kill-flagged anim effect still unstopped >0.5 s after its (non-looping) clip ended
##   ANIM_ORPHAN_LATE  anim orphan past its deadline by >1 s
##   DUP_LOOP          two or more unstopped looping effects of the same system on the same unit and bone (>0.3 s)
## The ranked report is printed every leak_every seconds and at exit ("LEAKRPT" lines).

var match_ref = null
var main = null

const SAMPLE := 0.1
const REF_EVERY := 0.5
const FLAG_NAMES := ["LOOP_UNREF", "BUFF_END_ALIVE", "BUFF_END_LINGER", "DEAD_HOST", "NOT_IN_TREE", "AGE_ONESHOT",
		"OVERDUE_FREE", "ANIM_UNTRACKED", "ANIM_STALE", "ANIM_PAST_END", "ANIM_PAST_CLIP", "ANIM_ORPHAN_LATE", "DUP_LOOP"]

var _recs := {}        ## instance id -> record
var _done: Array = []  ## finished records (freed instances)
var _t_acc := 0.0
var _ref_t := -10.0
var _refs := {}        ## fx id -> root description
var _bound := {}       ## fx id -> {"buff": Buff, "unit": id, "ended": -1.0}
var _dead_since := {}  ## unit id -> first time seen dead
var _leak_age := 10.0
var _every := 150.0
var _next_report := 150.0
var _limit := 600.0
var _flag_lines := 0
var _spawned := 0
var _printed_final := false
var _closure_hosts := {}   ## unit id -> true while it carries a buff with an on_expire / on_interval closure (may hold effects)
var _dup_seen := {}    ## "host|name|bone" -> first time seen duplicated


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--leak_age="):
			_leak_age = float(a.substr(11))
		elif a.begins_with("--leak_every="):
			_every = float(a.substr(13))
		elif a.begins_with("--time="):
			_limit = float(a.substr(7))
	_next_report = _every
	get_tree().node_added.connect(_on_node_added)
	G.match_over.connect(func(_w): _final())
	print("VFXLEAK probe armed (leak_age=%.0f s, report every %.0f s)" % [_leak_age, _every])


func _exit_tree() -> void:
	_final()


func _final() -> void:
	if _printed_final:
		return
	_printed_final = true
	_sample(true)
	_report("FINAL")


func _now() -> float:
	return float(match_ref.time) if match_ref != null else Time.get_ticks_msec() / 1000.0


# ===================================================================== spawn capture
func _on_node_added(n: Node) -> void:
	if not (n is LolVfx):
		return
	var stack: Array = get_stack()
	var src := ""
	var via := ""
	for f in stack:
		var s := String(f.source)
		if s.ends_with("lol_vfx.gd") or s.ends_with("vfx_leak_probe.gd"):
			continue
		var fn := "%s:%s:%d" % [s.get_file().trim_suffix(".gd"), f.function, f.line]
		if s.ends_with("kit_util.gd"):
			if via == "":
				via = String(f.function)
			continue
		src = fn
		break
	if src == "":
		src = "(engine/no script frame)"
	var par = n.get_parent()
	var sysname := String(n.name)
	if sysname.begins_with("@"):
		sysname = _system_name(n)
	var rec := {"id": n.get_instance_id(), "n": n, "name": sysname, "t0": _now(), "src": src, "via": via,
			"flags": {}, "age": 0.0, "kind": "", "host": "", "loop": false, "stopped_seen": -1.0, "bone": "",
			"anim": false, "clip": ""}
	if par is Unit:
		rec.host = par.display_name
	elif par is Missile:
		rec.host = "(missile)"
	elif par is LolVfx:
		rec.host = "(nested)"
	else:
		rec.host = "(world)"
	_recs[rec.id] = rec
	_spawned += 1


## Godot renames a node on a sibling-name clash ("@Node3D@489"): find the system by its definition.
var _name_cache := {}   ## "emitters|dur" -> candidate system names


func _system_name(n) -> String:
	var d: Dictionary = n.def
	var sig := "%d|%s" % [d.get("emitters", []).size(), str(d.get("dur", 0))]
	var cand: Array = _name_cache.get(sig, [])
	for k in cand:
		if is_same(LolVfx._db.get(k), d):
			return k
	for k in LolVfx._db.keys():
		if is_same(LolVfx._db[k], d):
			if not _name_cache.has(sig):
				_name_cache[sig] = []
			_name_cache[sig].append(k)
			return k
	return "(?)"


# ===================================================================== sampling
func _process(delta: float) -> void:
	if match_ref == null:
		return
	_t_acc += delta
	if _t_acc < SAMPLE:
		return
	_t_acc = 0.0
	_sample(false)
	var now := _now()
	if now >= _next_report:
		_next_report += _every
		_report("t=%.0f" % now)


func _collect_refs(obj, tag: String, depth: int, seen: Dictionary) -> void:
	if obj == null or depth > 3:
		return
	if obj is Object and not is_instance_valid(obj):
		return
	if obj is LolVfx:
		if not _refs.has(obj.get_instance_id()):
			_refs[obj.get_instance_id()] = tag
		return
	if obj is Node:
		# never walk the scene graph (units, missiles ...); a plain container node (Annie's frenzy holder) only
		# lends its own effect children
		if not (obj is Unit) and not (obj is Missile):
			for c in obj.get_children():
				if c is LolVfx and not _refs.has(c.get_instance_id()):
					_refs[c.get_instance_id()] = tag + "/container"
		return
	if obj is Array:
		var k := 0
		for x in obj:
			_collect_refs(x, tag, depth + 1, seen)
			k += 1
			if k > 64:
				break
		return
	if obj is Dictionary:
		var k := 0
		for key in obj.keys():
			_collect_refs(obj[key], tag, depth + 1, seen)
			k += 1
			if k > 64:
				break
		return
	if obj is Object:
		var iid: int = obj.get_instance_id()
		if seen.has(iid):
			return
		seen[iid] = true
		for p in obj.get_property_list():
			if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			var tp := int(p.type)
			if tp != TYPE_OBJECT and tp != TYPE_ARRAY and tp != TYPE_DICTIONARY:
				continue
			var v = obj.get(p.name)
			if v != null:
				_collect_refs(v, "%s.%s" % [tag, p.name], depth + 1, seen)


## Shallow scan of a node's script variables for effects it holds (a structure's _timer_fx, a relic's lol_fx ...).
func _collect_node_fields(n: Node, tag: String, seen: Dictionary) -> void:
	for p in n.get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var tp := int(p.type)
		if tp != TYPE_OBJECT and tp != TYPE_ARRAY and tp != TYPE_DICTIONARY:
			continue
		var v = n.get(p.name)
		if v != null:
			_collect_refs(v, "%s.%s" % [tag, p.name], 1, seen)


func _scan_refs() -> void:
	_refs.clear()
	var seen := {}
	for u in match_ref.units.duplicate():
		if not is_instance_valid(u):
			continue
		_collect_node_fields(u, "unit", {})   # own `seen`: the effects array reached from here must not shadow the deeper scan below
		if u.get("anim_ev") != null:
			_collect_refs(u.anim_ev, "anim", 0, seen)
		for e in u.effects:
			_collect_refs(e, "effect:%s" % e.id, 0, seen)
		if u is Champion:
			if u.kit != null:
				_collect_refs(u.kit, "kit", 0, seen)
			for ab in u.abilities:
				if ab != null:
					_collect_refs(ab, "ability", 0, seen)
			if u.passive != null:
				_collect_refs(u.passive, "passive", 0, seen)
	# effects kept by match-level objects (relics ...)
	for r in match_ref.get("relics") if match_ref.get("relics") != null else []:
		if is_instance_valid(r):
			_collect_node_fields(r, "relic", {})


func _track_buffs() -> void:
	_closure_hosts.clear()
	for u in match_ref.units.duplicate():
		if not is_instance_valid(u):
			continue
		for b in u.buffs:
			if b.on_expire.is_valid() or b.on_interval.is_valid():
				_closure_hosts[u.get_instance_id()] = true
			var fxs: Array = []
			var bv = b.vfx
			if bv != null and is_instance_valid(bv):
				if bv is LolVfx:
					fxs.append(bv)
				elif bv is Node:
					for c in bv.get_children():
						if c is LolVfx:
							fxs.append(c)
			if "extra_fx" in b:
				for x in b.extra_fx:
					if x != null and is_instance_valid(x) and x is LolVfx:
						fxs.append(x)
			for fx in fxs:
				if is_instance_valid(fx):
					var fid: int = fx.get_instance_id()
					if not _bound.has(fid):
						_bound[fid] = {"buff": b, "unit": u.get_instance_id(), "ended": -1.0, "bid": b.id}
					elif _bound[fid].buff != b:
						# the effect was handed to another buff (shared slow indicator): it is bound to that one now
						_bound[fid].buff = b
						_bound[fid].ended = -1.0
						_bound[fid].bid = b.id


func _flag(rec: Dictionary, kind: String, info: String = "") -> void:
	if rec.flags.has(kind):
		return
	rec.flags[kind] = {"age": rec.age, "info": info}
	if _flag_lines < 600:
		_flag_lines += 1
		print("LEAKFLAG t=%.1f %s %s host=%s src=%s via=%s age=%.1f %s" % [_now(), kind, rec.name, rec.host, rec.src, rec.via, rec.age, info])


func _sample(final: bool) -> void:
	var now := _now()
	_track_buffs()
	if now - _ref_t >= REF_EVERY and not final:   # (the exit-time sample runs while the match is being torn down: no ref scan, no LOOP_UNREF)
		_ref_t = now
		_scan_refs()
	# unit death bookkeeping
	for u in match_ref.units.duplicate():
		if not is_instance_valid(u):
			continue
		var uid: int = u.get_instance_id()
		if u.dead:
			if not _dead_since.has(uid):
				_dead_since[uid] = now
		else:
			_dead_since.erase(uid)
	var dup_count := {}
	var ids: Array = _recs.keys()
	for id in ids:
		var rec: Dictionary = _recs[id]
		var n = rec.n
		if not is_instance_valid(n):
			rec.erase("n")
			rec["gone"] = now
			_done.append(rec)
			_recs.erase(id)
			continue
		var fx: LolVfx = n
		var age: float = LolVfx._now - fx._born if fx._born > 0.0 or fx._t > 0.0 else 0.0
		if not fx.is_inside_tree():
			age = now - rec.t0
		rec.age = maxf(age, 0.0)
		rec.loop = fx._loop
		rec.kind = "loop" if fx._loop else "oneshot"
		var stopped: bool = fx._stopped
		if stopped and rec.stopped_seen < 0.0:
			rec.stopped_seen = now
		var par = fx.get_parent()
		var host = par if par is Unit else null
		if rec.bone == "":
			rec.bone = String(fx._opts.get("bone", "-"))
		if fx.has_meta("anim_ev"):
			rec.anim = true
			if host != null and host.get("anim_ev") != null and rec.clip == "":
				rec.clip = String(host.anim_ev._clip)
		if rec.src.begins_with("map_ambient"):
			continue   # map ambience lives for the whole match
		var fid: int = id
		var referenced: bool = _refs.has(fid) or (_bound.has(fid) and not _bound[fid].buff.removed) 				or (host != null and _closure_hosts.has(host.get_instance_id()))
		# --- tree membership
		if not fx.is_inside_tree():
			if age > 1.0:
				_flag(rec, "NOT_IN_TREE")
			continue
		# --- one-shot / stopped overdue
		if not fx._loop and not stopped:
			var cap := minf(float(fx._dur), float(fx._opts.get("max_life", LolVfx.MAX_ONESHOT)))
			if age > maxf(3.0 * (cap + 0.2), 2.0) and age > cap + 2.0:
				_flag(rec, "AGE_ONESHOT", "dur=%.1f cap=%.1f" % [fx._dur, cap])
		if stopped:
			var due: float = fx._free_at
			if due >= 0.0 and age > due + 1.5 + 0.1:
				_flag(rec, "OVERDUE_FREE", "free_at=%.1f" % due)
		# --- dead host
		if host != null and fx._loop and not stopped and _dead_since.has(host.get_instance_id()) and not rec.src.contains("_shatter_fx") and not rec.src.contains("structure:on_died"):
			if now - float(_dead_since[host.get_instance_id()]) > 1.5 and not rec.anim:
				_flag(rec, "DEAD_HOST", "host dead %.1fs" % (now - float(_dead_since[host.get_instance_id()])))
		# --- unreferenced loop
		if not final and fx._loop and not stopped and not rec.anim and age > _leak_age and not referenced \
				and fx._mis.is_empty() and not _nested(fx) and not _dying(fx) and not fx._has_follow 				and not rec.src.contains("_shatter_fx"):
			var pdesc := ""
			if par != null:
				var gp = par.get_parent()
				pdesc = " parent=%s(%s) grand=%s%s" % [par.name, par.get_class(), str(gp.name) if gp != null else "-",
						(" " + gp.display_name + " kind=" + str(gp.kind) + " dead=" + str(gp.dead) + " in_tree=" + str(gp.is_inside_tree()) + " buffs=" + str(gp.buffs.map(func(b): return "%s:%.1f" % [b.id, b.remaining]))) if gp is Unit else ""]
			_flag(rec, "LOOP_UNREF", "%s dyn=%s wake=%.1f free_at=%.1f%s" % ["world" if host == null else "attached", fx._dynamic,
					fx._wake, fx._free_at, pdesc])
		# --- buff-bound effects whose buff ended
		if _bound.has(fid):
			var bd: Dictionary = _bound[fid]
			if bd.buff.removed:
				if bd.ended < 0.0:
					bd.ended = now
				rec["ended"] = bd.ended
				var since: float = now - bd.ended
				if since > 0.6:
					_flag(rec, "BUFF_END_LINGER" if stopped else "BUFF_END_ALIVE", "buff=%s ended %.1fs ago" % [bd.bid, since])
		# --- animation events
		if rec.anim and host != null and host.get("anim_ev") != null:
			_check_anim(rec, fx, host, host.anim_ev, stopped, age, now)
		# --- duplicates
		if fx._loop and not stopped and host != null:
			var key := "%d|%s|%s" % [host.get_instance_id(), rec.name, rec.bone]
			if not dup_count.has(key):
				dup_count[key] = []
			dup_count[key].append(rec)
	for key in dup_count:
		var lst: Array = dup_count[key]
		if lst.size() > 1:
			if rec_multi(lst[0]):
				continue
			if not _dup_seen.has(key):
				_dup_seen[key] = now
			elif now - float(_dup_seen[key]) > 0.3:
				for r in lst:
					_flag(r, "DUP_LOOP", "x%d" % lst.size())
		else:
			_dup_seen.erase(key)
	# forget bound entries whose effect is gone
	for fid in _bound.keys():
		if not is_instance_id_valid(fid):
			_bound.erase(fid)


## True when the effect or an ancestor is already queued for deletion (freed at the end of this frame).
func _dying(fx: Node) -> bool:
	var a: Node = fx
	var k := 0
	while a != null and k < 6:
		if a.is_queued_for_deletion():
			return true
		a = a.get_parent()
		k += 1
	return false


## True when the effect hangs below a missile or another effect (child systems of a missile / carrier nodes).
func _nested(fx: Node) -> bool:
	var a: Node = fx.get_parent()
	var k := 0
	while a != null and k < 5:
		if a is Missile or a is LolVfx:
			return true
		a = a.get_parent()
		k += 1
	return false


## Systems that legitimately exist once per source on the same unit (every snowballer's own mark).
func rec_multi(r: Dictionary) -> bool:
	return r.name == "Summoner_Snowball_Tagged"


func is_instance_id_valid(id: int) -> bool:
	return is_instance_valid(instance_from_id(id))


func _check_anim(rec: Dictionary, fx: LolVfx, host, ae, stopped: bool, age: float, now: float) -> void:
	if stopped:
		return
	var fid: int = rec.id
	var in_live := false
	for l in ae._live:
		if is_same(l[1], fx):
			in_live = true
			var ev: Dictionary = l[0]
			if int(l[2]) != int(ae._serial):
				_flag(rec, "ANIM_STALE", "serial %d vs %d clip=%s" % [l[2], ae._serial, ae._clip])
			else:
				if float(ev.te) >= 0.0 and float(ae._t) > float(ev.te) + 0.5 and (not ae._looping or int(l[3]) == int(ae._pass)):
					_flag(rec, "ANIM_PAST_END", "t=%.2f te=%.2f clip=%s" % [ae._t, ev.te, ae._clip])
				if not ae._looping and bool(ev.kill) and float(ae._t) > float(ae._len) + 0.5 + 0.0:
					_flag(rec, "ANIM_PAST_CLIP", "t=%.2f len=%.2f clip=%s" % [ae._t, ae._len, ae._clip])
			break
	if in_live:
		return
	for o in ae._orphans:
		if is_same(o[0], fx):
			if float(ae._now()) > float(o[1]) + 1.0:
				_flag(rec, "ANIM_ORPHAN_LATE", "deadline passed %.1fs" % (float(ae._now()) - float(o[1])))
			return
	for x in ae._idle_fx:
		if is_same(x, fx):
			if host.dead and _dead_since.has(host.get_instance_id()) and now - float(_dead_since[host.get_instance_id()]) > 1.5:
				_flag(rec, "DEAD_HOST", "idle fx on dead unit")
			return
	if fx._loop and age > 0.5:
		_flag(rec, "ANIM_UNTRACKED", "clip=%s" % ae._clip)


# ===================================================================== report
func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _report(title: String) -> void:
	var all: Array = _done.duplicate()
	for id in _recs.keys():
		all.append(_recs[id])
	var groups := {}   # "FLAG|system|src" -> {count, ages, hosts}
	var by_flag := {}
	var loops := {}    # "system|src" -> lifetimes of loop instances
	for r in all:
		if r.loop:
			var lk := "%s | %s" % [r.name, r.src]
			if not loops.has(lk):
				loops[lk] = []
			loops[lk].append(float(r.age))
		for f in r.flags:
			var k := "%s|%s|%s" % [f, r.name, ("anim:" + String(r.clip)) if r.anim else r.src]
			if not groups.has(k):
				groups[k] = {"c": 0, "ages": [], "hosts": {}, "via": r.via}
			groups[k].c += 1
			if f.begins_with("BUFF_END") and r.has("ended"):
				groups[k].ages.append(float(r.get("gone", _now())) - float(r.ended))   # time the effect outlived its buff
			else:
				groups[k].ages.append(float(r.flags[f].age))
			groups[k].hosts[r.host] = true
			by_flag[f] = int(by_flag.get(f, 0)) + 1
	print("LEAKRPT ===== %s  match_t=%.0f  spawned=%d live=%d finished=%d flagged_instances=%d" % [title, _now(), _spawned, _recs.size(), _done.size(), _flagged_count(all)])
	var fl := ""
	for f in FLAG_NAMES:
		fl += " %s=%d" % [f, int(by_flag.get(f, 0))]
	print("LEAKRPT flags:" + fl)
	var an := 0
	var an_loop := 0
	var an_end := 0
	for r in all:
		if r.anim:
			an += 1
			if r.loop:
				an_loop += 1
	print("LEAKRPT anim-event/idle instances=%d (looping=%d)  loop systems seen=%d  clip-end particle stops: %s" % [an, an_loop, loops.size(), str(AnimEvents.stats.get("clip_end", {}))])
	var keys: Array = groups.keys()
	keys.sort_custom(func(a, b): return groups[a].c > groups[b].c or (groups[a].c == groups[b].c and _median(groups[a].ages) > _median(groups[b].ages)))
	var shown := 0
	for k in keys:
		var g = groups[k]
		var mx := 0.0
		for a in g.ages:
			mx = maxf(mx, float(a))
		var sp: PackedStringArray = k.split("|")
		print("LEAKRPT  %-16s n=%-4d typ=%5.1fs max=%5.1fs  %-42s src=%s%s hosts=%s" % [sp[0], g.c, _median(g.ages), mx, sp[1], sp[2],
				(" via=" + String(g.via)) if g.via != "" else "", ",".join(g.hosts.keys().slice(0, 4))])
		shown += 1
		if shown >= 40:
			break
	# stop -> free time of looping effects: how long an effect keeps showing after the code stopped it
	var stops := {}
	for r in all:
		if r.loop and float(r.stopped_seen) >= 0.0:
			var sk := "%s | %s" % [r.name, ("anim:" + String(r.clip)) if r.anim else r.src]
			if not stops.has(sk):
				stops[sk] = []
			stops[sk].append(float(r.get("gone", _now())) - float(r.stopped_seen))
	var sk2: Array = stops.keys()
	sk2.sort_custom(func(a, b): return _med_max(stops[a]) > _med_max(stops[b]))
	var n3 := 0
	for k in sk2:
		var a: Array = stops[k]
		if _med_max(a) < 1.2:
			break
		print("LEAKRPT  stop-linger n=%-4d med=%4.1fs max=%4.1fs  %s" % [a.size(), _median(a), _med_max(a), k])
		n3 += 1
		if n3 >= 20:
			break
	# loop inventory: longest-lived looping effects by source (what a human should sanity check)
	var lk2: Array = loops.keys()
	lk2.sort_custom(func(a, b): return _med_max(loops[a]) > _med_max(loops[b]))
	var n2 := 0
	for k in lk2:
		var a: Array = loops[k]
		var mx := 0.0
		for x in a:
			mx = maxf(mx, float(x))
		if mx < 8.0:
			break
		print("LEAKRPT  loop-life n=%-4d med=%5.1fs max=%6.1fs  %s" % [a.size(), _median(a), mx, k])
		n2 += 1
		if n2 >= 25:
			break


func _med_max(a: Array) -> float:
	var mx := 0.0
	for x in a:
		mx = maxf(mx, float(x))
	return mx


func _flagged_count(all: Array) -> int:
	var c := 0
	for r in all:
		if not r.flags.is_empty():
			c += 1
	return c
