extends Node
## [motion] stride diagnostics: dumps planted-foot tracks of every run clip of every champion / minion.
## tools/check.sh 200 -- --harness=res://src/debug/motion_stride.gd [--mclip=run_var2]

var main
var match_ref
var _done := false


func _process(_d: float) -> void:
	if _done or match_ref == null or match_ref.time < 0.5:
		return
	if "--mminions" in OS.get_cmdline_user_args() and match_ref.time < 100.0 or not match_ref.units.any(func(u): return u is Minion and u.minion_type == 2):
		match_ref.game_speed = 3.0
		return
	_done = true
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mclip="):
			only = a.substr(8)
	var seen := {}
	for u in match_ref.units:
		if u.anim_player == null or u._skel == null:
			continue
		var key: String = u.display_name
		if seen.has(key):
			continue
		seen[key] = true
		_dump(u, only)


func _dump(u, only: String) -> void:
	var ap: AnimationPlayer = u.anim_player
	var skel: Skeleton3D = u._skel
	var feet := []
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower().replace("_", "")
		if n in ["lbuffboneglbfootloc", "rbuffboneglbfootloc"] or n.contains("toe") or n.contains("ankle") or n in ["lfoot", "rfoot"]:
			feet.append(i)
	print("[feet] ", feet.map(func(i): return skel.get_bone_name(i)))
	print("[stride] %s feet=%s scale=%.4f strides=%s ms=%.0f" % [u.display_name, feet, u._skel_scale(), u._strides, u.stats.move_speed])
	if u is Minion:
		var bl := []
		for i in skel.get_bone_count():
			var n := skel.get_bone_name(i).to_lower()
			bl.append(n)
		print("   bones: ", bl)
	if feet.is_empty():
		return
	for an in ap.get_animation_list():
		var low := String(an).to_lower()
		if not (low.contains("run") or low.contains("haste")):
			continue
		if only != "" and low != only:
			continue
		var a := ap.get_animation(an)
		ap.play(an, 0.0, 1.0)
		var tr := []
		for i in 121:
			var t := a.length * float(i) / 120.0
			ap.seek(minf(t, a.length - 0.0001), true)
			var row := []
			for f in feet:
				var p: Vector3 = skel.get_bone_global_pose(f).origin
				row.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
			tr.append(row)
		print("[trace] ", JSON.stringify({"unit": u.display_name, "clip": an, "len": a.length, "tr": tr}))
