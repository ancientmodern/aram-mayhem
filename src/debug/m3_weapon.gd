extends Node
## [motion3] weapon-vs-hand diagnostic: per clip, the distance of the weapon bone to the nearest hand bone
## over the clip (a held weapon keeps a small, near-constant distance).
## tools/check.sh 1500 -- --champ=Lux --harness=res://src/debug/m3_weapon.gd --wbones=WEAPON

var main
var match_ref
var _done := false
var _f := 0


func _process(_d: float) -> void:
	_f += 1
	if _done or match_ref == null or G.player == null or _f < 20:
		return
	_done = true
	var wb: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wbones="):
			wb = Array(a.substr(9).to_lower().split(","))
	var u: Unit = G.player
	var ap: AnimationPlayer = u.anim_player
	var skel: Skeleton3D = u._skel
	var weps := []
	var hands := []
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if n in wb:
			weps.append(i)
		elif n.contains("hand") and not n.contains("buffbone") and not n.contains("finger") and not n.contains("thumb"):
			hands.append(i)
	print("[w] hold=", u._weapon_hold, " items=", u._weapon_hold.items if u._weapon_hold != null else [])
	print("[w] weps=%s hands=%s" % [weps.map(func(i): return skel.get_bone_name(i)), hands.map(func(i): return skel.get_bone_name(i))])
	if hands.is_empty() or weps.is_empty():
		get_tree().quit()
		return
	ap.active = true
	var names := Array(ap.get_animation_list())
	names.sort()
	for an in names:
		var a := ap.get_animation(an)
		ap.play(an, 0.0, 1.0)
		var mn := INF
		var mx := 0.0
		var tmax := 0.0
		var steps := 40
		for i in steps + 1:
			var t := a.length * float(i) / float(steps)
			ap.seek(minf(t, a.length - 0.0001), true)
			if u._weapon_hold != null and "--hold" in OS.get_cmdline_user_args():
				u._weapon_hold._hold()
			var dmin := INF
			for w in weps:
				for h in hands:
					dmin = minf(dmin, (skel.get_bone_global_pose(w).origin - skel.get_bone_global_pose(h).origin).length())
			mn = minf(mn, dmin)
			if dmin > mx:
				mx = dmin
				tmax = t
		print("[w] %-34s len=%5.2f dist min=%.2f max=%.2f (at %.2f)" % [an, a.length, mn, mx, tmax])
	get_tree().quit()
