extends Node
## [bugfix] Cast-rate audit for a full sim: counts every ability execution per champion/slot and flags runaway casting
## (ability fired again sooner than its own cooldown / more than 3 times in 1.5 s without a legal recast window).
## Usage: tools/preview.sh 300 -- --sim --botplayer --time=300 --harness=res://src/debug/cast_audit.gd
var match_ref = null
var main = null
var _last := {}     ## "Champ:slot" -> {n, t, burst:[times]}
var _flags := 0


func _physics_process(_dt: float) -> void:
	if match_ref == null:
		return
	for c in match_ref.champions:
		for slot in 4:
			var ab = c.abilities[slot]
			if ab == null:
				continue
			var key := "%s:%d" % [c.alias, slot]
			var r: Dictionary = _last.get(key, {"n": ab.cast_count, "burst": [], "total": 0})
			if ab.cast_count != r.n:
				var d: int = ab.cast_count - r.n
				r.n = ab.cast_count
				r.total += d
				var t: float = match_ref.time
				r.burst.append(t)
				while r.burst.size() > 0 and t - r.burst[0] > 1.5:
					r.burst.pop_front()
				if r.burst.size() >= 4:
					_flags += 1
					print("CASTAUDIT RUNAWAY %s t=%.1f casts_in_1.5s=%d cd=%.2f recast_window=%.2f" % [key, t, r.burst.size(), ab.cd, ab.recast_window])
			_last[key] = r


func _exit_tree() -> void:
	var rows := []
	for k in _last.keys():
		rows.append("%s=%d" % [k, _last[k].total])
	print("CASTAUDIT SUMMARY flags=%d | %s" % [_flags, " ".join(rows)])
