class_name AnimGraph
extends RefCounted
## League AnimationGraphData (extracted by tools/lol/extract_anim.py into data/anim/<alias>.json).
## Resolves League clip names (selectors, sequencers, condition nodes) into steps of exported .glb
## clips, and provides League blend times and attack/spell timing data.

const DEFAULT_BLEND := 0.15
const CAST_FPS := 30.0        ## League castFrame is authored at 30 fps (castFrame / 30 == mCastTime)

static var _cache := {}

var clips := {}               ## lower-case League clip name -> node dict
var blends := {}              ## "from>to" (lower) -> float | {"clip": name}
var attacks: Array = []
var crits: Array = []
var spells: Array = []
var stats := {}
var alias := ""


static func load_for(name: String) -> AnimGraph:
	var key := name.to_lower()
	if _cache.has(key):
		return _cache[key]
	var g: AnimGraph = null
	var p := "res://data/anim/%s.json" % key
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			g = AnimGraph.new()
			g._load(d)
	_cache[key] = g
	return g


func _load(d: Dictionary) -> void:
	alias = String(d.get("alias", ""))
	for k in d.get("clips", {}):
		clips[String(k).to_lower()] = d.clips[k]
	for k in d.get("blends", {}):
		blends[String(k).to_lower()] = d.blends[k]
	# nameless extra attacks still count (League defaults their clip to Attack<N>)
	attacks = d.get("attacks", []).filter(func(a): return a is Dictionary and not a.is_empty())
	crits = d.get("crits", []).filter(func(a): return a is Dictionary and a.has("name"))
	spells = d.get("spells", [])
	stats = d.get("stats", {})


func has_clip(n: String) -> bool:
	return clips.has(n.to_lower())


## First existing clip of the candidates ("" if none).
var _find_cache := {}


func find_clip(cands: Array) -> String:
	var key := ",".join(cands)
	var hit = _find_cache.get(key)
	if hit != null:
		return hit
	var res := ""
	for c in cands:
		var l := String(c).to_lower()
		if clips.has(l) and _playable(l, 0):
			res = l
			break
	_find_cache[key] = res
	return res


func _playable(n: String, depth: int) -> bool:
	var node = clips.get(n)
	if node == null or depth > 8:
		return false
	match String(node.get("type", "")):
		"Atomic":
			return node.get("anim") != null or node.get("xanim") != null
		"Selector", "ConditionFloat":
			for p in node.get("pairs", []):
				if _playable(String(p[0]).to_lower(), depth + 1):
					return true
		"Sequencer", "Parallel":
			for c in node.get("list", []):
				if _playable(String(c).to_lower(), depth + 1):
					return true
		"ConditionBool":
			return _playable(String(node.get("true", "")).to_lower(), depth + 1) \
					or _playable(String(node.get("false", "")).to_lower(), depth + 1)
	return false


## Resolve a clip into playable steps: [{anim, clip, loop}] (clip = atomic League name for blends).
## ctx keys: MoveSpeed, IsMoving, IsAlly, IsHomeguard, LookAtSpellTargetAngle, Facing, AttackSpeed ...
func resolve(n: String, ctx: Dictionary) -> Array:
	var out := []
	_resolve(n.to_lower(), ctx, out, 0)
	return out


func _resolve(n: String, ctx: Dictionary, out: Array, depth: int) -> void:
	var node = clips.get(n)
	if node == null or depth > 8:
		return
	match String(node.get("type", "")):
		"Atomic":
			var an = node.get("anim")
			if an == null:
				an = node.get("xanim")   # clip from the companion data/anim/clips/<alias>.glb ("x" library)
			if an != null:
				out.append({"anim": String(an), "clip": n, "loop": (int(node.get("flags", 0)) & 2) != 0})
		"Selector":
			var pairs: Array = node.get("pairs", []).filter(func(p): return _playable(String(p[0]).to_lower(), depth + 1))
			if pairs.is_empty():
				return
			var tot := 0.0
			for p in pairs:
				tot += maxf(float(p[1]), 0.0)
			var r := G.rng.randf() * tot
			var pick: String = String(pairs[0][0])
			for p in pairs:
				r -= maxf(float(p[1]), 0.0)
				if r <= 0.0:
					pick = String(p[0])
					break
			_resolve(pick.to_lower(), ctx, out, depth + 1)
		"Sequencer":
			for c in node.get("list", []):
				_resolve(String(c).to_lower(), ctx, out, depth + 1)
		"Parallel":
			var l: Array = node.get("list", [])
			if not l.is_empty():
				_resolve(String(l[0]).to_lower(), ctx, out, depth + 1)
		"ConditionFloat":
			var v := float(ctx.get(String(node.get("updater", "")), 0.0))
			var pairs2: Array = node.get("pairs", [])
			if pairs2.is_empty():
				return
			var pick2: String = String(pairs2[0][0])
			for p in pairs2:
				if v >= float(p[1]):
					pick2 = String(p[0])
			_resolve(pick2.to_lower(), ctx, out, depth + 1)
		"ConditionBool":
			var b := bool(ctx.get(String(node.get("updater", "")), false))
			var nm := String(node.get("true" if b else "false", ""))
			if nm == "" or not _playable(nm.to_lower(), depth + 1):
				nm = String(node.get("false" if b else "true", ""))
			_resolve(nm.to_lower(), ctx, out, depth + 1)


func loops(n: String) -> bool:
	var node = clips.get(n.to_lower())
	return node != null and (int(node.get("flags", 0)) & 2) != 0


## League blend time between clips (atomic and top-level names are both tried).
## Returns a float, or a String naming a transition clip to play in between.
func blend(from_atomic: String, from_top: String, to_atomic: String, to_top: String, fallback: float = DEFAULT_BLEND):
	for f in [from_atomic, from_top, "*"]:
		if f == "":
			continue
		for t in [to_atomic, to_top, "*"]:
			if t == "":
				continue
			var v = blends.get(f + ">" + t)
			if v == null:
				continue
			if v is Dictionary:
				return String(v.get("clip", ""))
			return float(v)
	return fallback


## Pick the basic attack (League mAttackProbability over basicAttack + extraAttacks).
func pick_attack(crit: bool) -> Dictionary:
	if crit and not crits.is_empty():
		return crits[0]
	if attacks.is_empty():
		return {}
	var tot := 0.0
	for a in attacks:
		tot += float(a.get("prob", 0.0))
	if tot <= 0.0:
		return attacks[0]
	var r := G.rng.randf() * tot
	for a in attacks:
		r -= float(a.get("prob", 0.0))
		if r <= 0.0 and float(a.get("prob", 0.0)) > 0.0:
			return a
	return attacks[0]


## League clip name an attack entry plays (default Attack1 for the basic, Attack<N> for extras, Crit).
func attack_clip(a: Dictionary, crit: bool) -> String:
	var c := String(a.get("clip", ""))
	if c != "" and _playable(c.to_lower(), 0):
		return c.to_lower()
	if crit:
		var cc := find_clip(["Crit", "Crit_Base", "Crit1"])
		if cc != "":
			return cc
	var i := attacks.find(a)
	var cands := ["Attack%d" % (maxi(i, 0) + 1), "Attack1", "Attack", "Attack1_Base", "Attack_Base"]
	return find_clip(cands)


## League windup fraction of the attack (0.3 + mAttackDelayCastOffsetPercent, or castTime/totalTime).
func windup_percent() -> float:
	if attacks.is_empty():
		return -1.0
	var a: Dictionary = attacks[0]
	if a.has("total_time") and a.has("cast_time") and float(a.total_time) > 0.0:
		return float(a.cast_time) / float(a.total_time)
	return 0.3 + float(a.get("cast_offset", 0.0))


func windup_modifier() -> float:
	if attacks.is_empty():
		return 1.0
	return float(attacks[0].get("cast_offset_as_ratio", 1.0))


func spell_for_slot(slot: int) -> Dictionary:
	for s in spells:
		if int(s.get("slot", -1)) == slot:
			return s
	return {}


func spell_for_clip(clip: String) -> Dictionary:
	var l := clip.to_lower()
	for s in spells:
		if String(s.get("clip", "")).to_lower() == l:
			return s
	return {}
